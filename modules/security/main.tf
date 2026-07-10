###############################################################################
# Frontend test runner — fixture access
#
# The base role + InitiateAuth policy let the runner authenticate test users
# via Cognito. This second policy lets it set up and tear down test state
# directly against DynamoDB and S3, bypassing the API.
#
# Scoping: by table and bucket prefix, not by partition key or test user sub.
# Per-userSub conditions would require either hardcoded tfvars or SSM data
# lookups and have low marginal value on staging — staging has no real user
# data and the role's trust policy already restricts assumption to the
# frontend repo via GitHub OIDC. Revisit if/when this role gets a production
# counterpart.
###############################################################################

resource "aws_iam_role_policy" "frontend_test_runner_fixtures" {
  name   = "studyspheres-${var.environment}-frontend-test-runner-fixtures"
  role   = aws_iam_role.frontend_test_runner.id
  policy = data.aws_iam_policy_document.frontend_test_runner_fixtures.json
}

data "aws_iam_policy_document" "frontend_test_runner_fixtures" {
  statement {
    sid    = "DynamoDBFixtureAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [
      var.user_profiles_table_arn,
      "${var.user_profiles_table_arn}/index/*",
      var.user_tokens_table_arn,
      var.user_shared_files_table_arn,
      "${var.user_shared_files_table_arn}/index/*",
    ]
  }

  statement {
    sid    = "S3FixtureObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.user_data_bucket_arn}/users/*"]
  }

  statement {
    sid       = "S3FixtureListAccess"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.user_data_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["users/*"]
    }
  }
}

# 1. Create the Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "studyspheres_${var.environment}_identity_pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = var.cognito_client_id
    provider_name           = "cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
    server_side_token_check = false
  }
}

# 2. Create the IAM Role for Authenticated Users
resource "aws_iam_role" "authenticated" {
  name = "studyspheres-${var.environment}-cognito-auth-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
}

# 3. Attach the Identity Pool to the Role
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.authenticated.arn
  }
}

# 4. Output the new Identity Pool ID so your React app can use it
output "identity_pool_id" {
  value = aws_cognito_identity_pool.main.id
}

# 5. Give the Authenticated Role access to the S3 User Data Bucket
resource "aws_iam_role_policy" "s3_access" {
  name   = "studyspheres-${var.environment}-s3-access"
  role   = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        # We dynamically build the bucket name based on the environment!
        Resource = ["arn:aws:s3:::studyspheres-${var.environment}-user-data/*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::studyspheres-${var.environment}-user-data"]
      }
    ]
  })
}


# 6. Test-only Cognito App Client
# Used exclusively by pytest to obtain idTokens via password auth without
# routing through the Hosted UI. Separate from the main app client so that
# the production auth surface stays SRP-only.
#
# Test users are created via scripts/create-test-users.ps1 and live in the
# same User Pool as real users. Identifiable by their @studyspheres-internal.test
# email domain — the .test TLD is RFC 2606 reserved and never resolves.
resource "aws_cognito_user_pool_client" "test_client" {
  name         = "studyspheres-${var.environment}-test-client"
  user_pool_id = var.cognito_user_pool_id

  # Password auth is the simple path for boto3.initiate_auth.
  # Refresh token auth lets long pytest sessions survive past 1 hour.
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # No client secret — test code reads username/password from .env.test
  # or SSM, sends them to initiate_auth, gets tokens back. No SECRET_HASH math.
  generate_secret = false

  # Short-lived tokens reduce blast radius if one ever leaks via test logs.
  # Pytest sessions are minutes, not hours.
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # No OAuth flows. This client is API-only — the Hosted UI must never
  # accept it as a valid redirect target.
  supported_identity_providers = ["COGNITO"]

  # Prevent enumeration attacks. Same setting as production should have.
  prevent_user_existence_errors = "ENABLED"

  # Don't read or write any user attributes through this client beyond the
  # auth flow itself. Profile data lives in DynamoDB (ADR-0001).
  read_attributes  = ["email", "email_verified"]
  write_attributes = []
}

output "test_client_id" {
  description = "Cognito App Client ID for pytest. Reference from .env.test as COGNITO_TEST_CLIENT_ID."
  value       = aws_cognito_user_pool_client.test_client.id
}