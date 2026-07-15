# path of this file C:\studyspheres\studyspheres-infrastructure\modules\compute\main.tf
# Fetch current AWS account ID dynamically to use in IAM policies
data "aws_caller_identity" "current" {}

locals {
  # Which SSM param holds the app's DB password: the master credential when
  # connecting as postgres, the app role's when opted in (ADR-0004 Option B).
  # Mirrors the same PG_USER-keyed selection in app.py's ensure_ssm_secrets.
  db_password_param = var.db_app_user == "postgres" ? "PG_PASSWORD" : "PG_APP_PASSWORD"
}

# 1. AWS Systems Manager (SSM) Parameters for Secrets
# These are created once manually or via CI — Terraform just references them
resource "aws_ssm_parameter" "db_password" {
  name        = "/studyspheres/${var.environment}/PG_PASSWORD"
  description = "Database password for ${var.environment}"
  type        = "SecureString"
  value       = var.db_password
  lifecycle {
    ignore_changes = [value] # Don't overwrite if manually updated in console
  }
}

# Password for the dedicated non-owner app role (RLS enforcement, ADR-0004
# Option B). Created only for environments that opt in via db_app_password;
# the role itself is manual DDL (SSM -> psql), like the rest of the pg schema.
resource "aws_ssm_parameter" "app_db_password" {
  count       = var.db_app_password == "" ? 0 : 1
  name        = "/studyspheres/${var.environment}/PG_APP_PASSWORD"
  description = "Non-owner app role (${var.db_app_user}) database password for ${var.environment}"
  type        = "SecureString"
  value       = var.db_app_password
  lifecycle {
    ignore_changes = [value] # Don't overwrite if manually updated in console
  }
}

# 2. SQS Queue for Background Tasks
resource "aws_sqs_queue" "task_queue" {
  name                       = "studyspheres-${var.environment}-tasks"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300
}

# 3. IAM Role & Instance Profile for EC2
resource "aws_iam_role" "ec2_role" {
  name = "studyspheres-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "app_permissions" {
  name = "studyspheres-${var.environment}-app-permissions"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:*"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["sqs:*"]
        Resource = [aws_sqs_queue.task_queue.arn]
      },
      {
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = ["*"]
      },
      {
        # App backend manages user tier/lifecycle in Cognito (ADR-0001):
        # AdminGetUser/AdminUpdateUserAttributes/AdminDeleteUser for profile+tier,
        # ListUsers for the admin analytics endpoint. Scoped to this env's pool only.
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminUpdateUserAttributes",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:ListUsers"
        ]
        Resource = [
          "arn:aws:cognito-idp:us-east-1:${data.aws_caller_identity.current.account_id}:userpool/${var.cognito_pool_id}"
        ]
      },
      {
        # Allow EC2 to read ALL secrets under /studyspheres/{env}/
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "kms:Decrypt"
        ]
        Resource = [
          "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/studyspheres/${var.environment}/*",
          "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "studyspheres-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# 4. Security Groups
resource "aws_security_group" "alb_sg" {
  name   = "studyspheres-${var.environment}-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "studyspheres-${var.environment}-ec2-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. Application Load Balancer
resource "aws_lb" "main" {
  name               = "studyspheres-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name     = "studyspheres-${var.environment}-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# 6. Auto Scaling Group & Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "studyspheres-${var.environment}-"
  image_id      = "ami-04b70fa74e45c3917"
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # This script runs on every new EC2 instance boot.
  # It fetches all secrets from SSM and builds the .env file automatically.
  # No manual SSH or nano required.
  user_data = base64encode(<<EOF
#!/bin/bash
set -e

LOG="/var/log/studyspheres-init.log"
exec > >(tee -a $LOG) 2>&1
echo "=== StudySpheres EC2 Init: $(date) ==="

# 1. Update and install base tools
apt-get update -y
apt-get install -y unzip python3-pip python3-venv jq curl libpq-dev postgresql-client

# 2. Install AWS CLI v2
if ! command -v aws &> /dev/null; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  ./aws/install
  rm -rf aws awscliv2.zip
fi

# 3. Setup App Directory
mkdir -p /opt/studyspheres
cd /opt/studyspheres

# 4. Download and Install App from correct staging S3 bucket
echo "Downloading app artifact..."
aws s3 cp s3://studyspheres-${var.environment}-user-data/deployments/backend.zip . || echo "WARNING: No artifact found in S3 yet. EC2 will start empty."

if [ -f "backend.zip" ]; then
    unzip -o backend.zip
    rm backend.zip
    rm -rf venv
    python3 -m venv venv
    ./venv/bin/pip install -r requirements.txt --quiet
    echo "App installed successfully."
else
    echo "No backend.zip found - skipping app install."
fi

# 5. Fetch ALL secrets from SSM Parameter Store
echo "Fetching secrets from SSM..."
REGION="us-east-1"
ENV="${var.environment}"

fetch_secret() {
  aws ssm get-parameter \
    --name "/studyspheres/$ENV/$1" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region $REGION 2>/dev/null || echo ""
}

DB_PASSWORD=$(fetch_secret "${local.db_password_param}")
CLIENT_SECRET=$(fetch_secret "CLIENT_SECRET")
GOOGLE_API_KEY=$(fetch_secret "GOOGLE_API_KEY")

if [ -z "$DB_PASSWORD" ]; then
  echo "ERROR: Could not fetch ${local.db_password_param} from SSM. Check IAM permissions."
fi
if [ -z "$CLIENT_SECRET" ]; then
  echo "ERROR: Could not fetch CLIENT_SECRET from SSM. Check IAM permissions."
fi
if [ -z "$GOOGLE_API_KEY" ]; then
  echo "ERROR: Could not fetch GOOGLE_API_KEY from SSM. Check IAM permissions."
fi

# 6. Build complete .env file from Terraform variables + SSM secrets
echo "Writing .env file..."
cat <<EOT > /opt/studyspheres/.env
# Auto-generated by EC2 user data script on $(date)
# Do NOT edit manually — changes will be lost on next instance launch
# To change values: update Terraform variables or SSM parameters and redeploy

ENV=${var.environment}
AWS_REGION=us-east-1

# Cognito
COGNITO_POOL_ID=${var.cognito_pool_id}
COGNITO_CLIENT_ID=${var.cognito_client_id}
COGNITO_DOMAIN=${var.cognito_domain}
COGNITO_REDIRECT_URI=https://${var.environment == "production" ? "study-spheres.com" : "${var.environment}.study-spheres.com"}/callback
CLIENT_SECRET=$CLIENT_SECRET

# Database
PG_HOST=${replace(var.db_endpoint, ":5432", "")}
PG_PORT=5432
PG_DB_NAME=studyspheres
PG_USER=${var.db_app_user}
PG_PASSWORD=$DB_PASSWORD

# S3
S3_BUCKET_NAME=studyspheres-${var.environment}-user-data

# DynamoDB
DYNAMODB_TABLE_PREFIX=${var.environment}-

# SQS
SQS_QUEUE_URL=${aws_sqs_queue.task_queue.id}

# Gemini
GOOGLE_API_KEY=$GOOGLE_API_KEY

# Admin
ADMIN_EMAIL=caylee.mcshane@ailearninghubus.com
EOT

echo ".env written successfully."
chmod 600 /opt/studyspheres/.env

# 7. Create and Start Systemd Service
cat <<'EOT' > /etc/systemd/system/studyspheres.service
[Unit]
Description=Gunicorn daemon for StudySpheres
After=network.target

[Service]
User=root
WorkingDirectory=/opt/studyspheres
EnvironmentFile=/opt/studyspheres/.env
ExecStart=/opt/studyspheres/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable studyspheres
systemctl restart studyspheres
echo "=== Init complete: $(date) ==="
EOF
  )

  # Force new instances to pick up latest launch template changes
  update_default_version = true
}

resource "aws_autoscaling_group" "app" {
  name                = "studyspheres-${var.environment}-asg"
  vpc_zone_identifier = var.private_subnet_ids

  min_size         = 1
  max_size         = var.environment == "production" ? 3 : 1
  desired_capacity = 1

  target_group_arns = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "studyspheres-${var.environment}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}
