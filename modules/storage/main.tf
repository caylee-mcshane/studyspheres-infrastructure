# ==========================================
# 1. BUCKETS & PUBLIC ACCESS BLOCKS
# ==========================================

resource "aws_s3_bucket" "web_app" {
  bucket        = "studyspheres-${var.environment}-web-frontend"
  force_destroy = true # Useful for staging teardowns
}

resource "aws_s3_bucket" "app_data" {
  bucket = "studyspheres-${var.environment}-user-data"
}

# Block ALL public access on BOTH buckets
resource "aws_s3_bucket_public_access_block" "web_block" {
  bucket                  = aws_s3_bucket.web_app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "data_block" {
  bucket                  = aws_s3_bucket.app_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# 2. CORS FOR COMMUNITY PRESIGNED URLS
# ==========================================

resource "aws_s3_bucket_cors_configuration" "data_cors" {
  bucket = aws_s3_bucket.app_data.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"] # Note: Lock this down to your specific domains in Production
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ==========================================
# 3. CLOUDFRONT DISTRIBUTION & OAC
# ==========================================

resource "aws_cloudfront_origin_access_control" "web_oac" {
  name                              = "studyspheres-${var.environment}-web-oac"
  description                       = "OAC for Study Spheres ${var.environment} Web Bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "web_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Origin 1: S3 bucket for frontend
  origin {
    domain_name              = aws_s3_bucket.web_app.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.web_app.id
    origin_access_control_id = aws_cloudfront_origin_access_control.web_oac.id
  }

  # Origin 2: ALB for backend API
  origin {
    domain_name = var.alb_dns_name
    origin_id   = var.alb_dns_name

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 5
      origin_read_timeout      = 60
    }
  }

  # Default: serve frontend from S3
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.web_app.id
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # /api/* — forward to ALB, no caching
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.alb_dns_name
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    compress               = true
  }

  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ==========================================
# 4. S3 BUCKET POLICY (ALLOW CLOUDFRONT)
# ==========================================

resource "aws_s3_bucket_policy" "web_policy" {
  bucket = aws_s3_bucket.web_app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web_app.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.web_distribution.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# 5. OUTPUTS
# ==========================================

output "cloudfront_domain" {
  description = "The CloudFront Domain Name to map Route 53 to"
  value       = aws_cloudfront_distribution.web_distribution.domain_name
}

output "data_bucket_name" {
  value = aws_s3_bucket.app_data.id
}

output "user_data_bucket_arn" {
  description = "ARN of the user data S3 bucket — used by security module to scope frontend test runner fixture permissions"
  value       = aws_s3_bucket.app_data.arn
}

