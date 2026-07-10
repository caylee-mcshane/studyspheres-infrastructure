# GitHub Actions OIDC integration
#
# Lets GitHub-hosted workflows assume AWS roles without long-lived access
# keys. Account-level OIDC provider (one per AWS account) + repo-scoped
# IAM roles that workflows assume on demand.
#
# Setup flow:
#   1. terraform apply creates the OIDC provider and the frontend test
#      runner role
#   2. terraform output frontend_test_runner_role_arn → copy to GitHub
#      Secrets as AWS_ROLE_TO_ASSUME in the studyspheres-frontend repo
#   3. Workflows use aws-actions/configure-aws-credentials@v4 with that
#      role-to-assume value; no access keys involved
#
# Security model: the role can ONLY be assumed by workflows running in
# the specific GitHub repo named in the trust policy. Other repos in
# the same GitHub org cannot assume it, even with identical names.

# ----- OIDC provider (one per AWS account) ------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC root CA thumbprints. AWS now performs full chain
  # validation on GitHub's tokens regardless of these, but the field
  # is still required by the API. List sourced from:
  # https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name = "github-actions"
  }
}

# ----- Frontend test runner role ----------------------------------------

resource "aws_iam_role" "frontend_test_runner" {
  name        = "studyspheres-${var.environment}-frontend-test-runner"
  description = "Assumed by GitHub Actions in studyspheres-frontend for E2E + Lighthouse auth"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Confirms the token was issued for AWS STS — defense against
            # token misuse if it ever leaks
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # The :* trailing wildcard allows any branch, PR, tag, or
            # environment in this specific repo. To tighten:
            #   ":ref:refs/heads/main"        — main branch only
            #   ":pull_request"               — PRs only
            #   ":environment:production"     — production env only
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/studyspheres-frontend:*"
          }
        }
      }
    ]
  })

  tags = {
    Component = "ci"
  }
}

# Permissions: minimum needed for the test workflows.
# InitiateAuth scoped to the staging user pool — the role cannot use any
# Cognito API beyond authenticating, cannot touch other pools, and the
# test users it can authenticate as are limited by which test users
# actually exist with USER_PASSWORD_AUTH enabled (i.e. the three
# permanent test accounts created by scripts/create-test-users.ps1).
resource "aws_iam_role_policy" "frontend_test_runner" {
  name = "studyspheres-${var.environment}-frontend-test-runner-policy"
  role = aws_iam_role.frontend_test_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InitiateAuthForTestUsers"
        Effect = "Allow"
        Action = "cognito-idp:InitiateAuth"
        # Cognito's IAM model scopes InitiateAuth at the user-pool level,
        # not the app-client level. The test client ID is supplied at
        # call time (from GitHub Secrets) — without it, the role can't
        # authenticate against anything useful even if assumed.
        Resource = "arn:aws:cognito-idp:${var.aws_region}:*:userpool/${var.cognito_user_pool_id}"
      }
    ]
  })
}

# ----- Outputs ----------------------------------------------------------

output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider. Reusable by other repos' IAM roles."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "frontend_test_runner_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes for frontend tests. Copy to the studyspheres-frontend repo's AWS_ROLE_TO_ASSUME secret."
  value       = aws_iam_role.frontend_test_runner.arn
}
