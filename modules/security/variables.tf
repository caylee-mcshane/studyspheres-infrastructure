variable "environment" {
  description = "The deployment environment (e.g., staging, production)"
  type        = string
}

variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "cognito_user_pool_id" {
  description = "The ID of the manually created Cognito User Pool"
  type        = string
}

variable "cognito_client_id" {
  description = "The Client ID of the manually created Cognito App Client"
  type        = string
}

# Added to scope GitHub Actions OIDC role trust policies to a specific
# GitHub organization or user. Used by github-actions-oidc.tf.
variable "github_org" {
  description = "GitHub organization or user that owns the studyspheres repos. Scopes IAM role trust policies."
  type        = string
  default     = "caylee-mcshane"
}

variable "user_profiles_table_arn" {
  description = "ARN of the UserProfiles DynamoDB table. Scopes frontend test runner fixture permissions."
  type        = string
}

variable "user_tokens_table_arn" {
  description = "ARN of the UserTokens DynamoDB table."
  type        = string
}

variable "user_shared_files_table_arn" {
  description = "ARN of the UserSharedFiles DynamoDB table."
  type        = string
}

variable "user_data_bucket_arn" {
  description = "ARN of the user data S3 bucket. Scopes test fixture S3 access to the users/ prefix."
  type        = string
}
