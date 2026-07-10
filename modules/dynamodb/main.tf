###############################################################################
# StudySpheres — DynamoDB Module
#
# Owns all NoSQL application tables. Every table is hardened with:
#   - PAY_PER_REQUEST billing       — no capacity tuning needed
#   - Point-in-time recovery (PITR) — 35-day continuous backups
#   - Server-side encryption        — AWS-owned KMS keys
#   - Deletion protection           — prevents accidental destroy
#   - Streams (where applicable)    — feeds future Lambdas
#   - Tagging via provider default_tags + per-table Name/Component
#
# Naming convention: ${environment}-TableName  (matches existing app.py constants)
# Exception: ProcessingSessions-${environment} (legacy convention preserved
#            so the running backend keeps working without a code change here)
###############################################################################


# ----------------------------------------------------------------------------
# 1. UserProfiles  [NEW]
#    Student profile + preference data. Replaces Cognito custom attributes
#    for non-identity fields (avatar, university, major, learning style, etc.).
#    Streams enabled — future personalization/recommendation Lambdas hook in
#    here without any application-code changes.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "user_profiles" {
  name         = "${var.environment}-UserProfiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userSub"

  attribute {
    name = "userSub"
    type = "S"
  }
  attribute {
    name = "email"
    type = "S"
  }
  attribute {
    name = "university"
    type = "S"
  }
  attribute {
    name = "major"
    type = "S"
  }
  attribute {
    name = "displayName"
    type = "S"
  }

  global_secondary_index {
    name            = "displayName-index"
    hash_key        = "displayName"
    projection_type = "KEYS_ONLY"   # we only need existence, not the full record
  }

  # Peer matching: "all CS grad students at CSUSM"
  global_secondary_index {
    name            = "university-major-index"
    hash_key        = "university"
    range_key       = "major"
    projection_type = "ALL"
  }

  # Admin / support lookups by email
  global_secondary_index {
    name            = "email-index"
    hash_key        = "email"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-UserProfiles"
    Component = "user-profiles"
  }
}


# ----------------------------------------------------------------------------
# 2. UserTokens  [RECREATED with userSub PK — was "userId"]
#    Token balance, monthly quota, promo redemption history.
#    Frequent read/write path (every AI generation deducts tokens),
#    so streams are intentionally OFF to save cost and noise.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "user_tokens" {
  name         = "${var.environment}-UserTokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userSub"

  attribute {
    name = "userSub"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-UserTokens"
    Component = "billing"
  }
}


# ----------------------------------------------------------------------------
# 3. PromoCodes
#    Static lookup table for promo codes.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "promo_codes" {
  name         = "${var.environment}-PromoCodes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "promoCode"

  attribute {
    name = "promoCode"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-PromoCodes"
    Component = "billing"
  }
}


# ----------------------------------------------------------------------------
# 4. AnalyticsEvents
#    Per-event log of every AI tool invocation: tool, status, cost, model.
#    GSI on userSub+timestamp powers per-user analytics views.
#    GSI on tool+timestamp powers product-wide tool usage dashboards.
#    Streams enabled — future aggregation Lambda can roll up stats hourly.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "analytics_events" {
  name         = "${var.environment}-AnalyticsEvents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "eventId"

  attribute {
    name = "eventId"
    type = "S"
  }
  attribute {
    name = "userSub"
    type = "S"
  }
  attribute {
    name = "tool"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name            = "userSub-timestamp-index"
    hash_key        = "userSub"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "tool-timestamp-index"
    hash_key        = "tool"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-AnalyticsEvents"
    Component = "analytics"
  }
}


# ----------------------------------------------------------------------------
# 5. SupportTickets
#    User-submitted support requests.
#    GSI on userSub+createdAt for the user's "my tickets" view.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "support_tickets" {
  name         = "${var.environment}-SupportTickets"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticketId"

  attribute {
    name = "ticketId"
    type = "S"
  }
  attribute {
    name = "userSub"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "userSub-createdAt-index"
    hash_key        = "userSub"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-SupportTickets"
    Component = "support"
  }
}


# ----------------------------------------------------------------------------
# 6. CommunityPosts
#    Posts in the community feed.
#    GSI on userSub+createdAt for the user's "my posts" view.
#    Streams enabled — future moderation Lambda + recommendation index updates.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "community_posts" {
  name         = "${var.environment}-CommunityPosts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "postId"

  attribute {
    name = "postId"
    type = "S"
  }
  attribute {
    name = "userSub"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "userSub-createdAt-index"
    hash_key        = "userSub"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-CommunityPosts"
    Component = "community"
  }
}


# ----------------------------------------------------------------------------
# 7. CommunityComments
#    Comments on community posts.
#    GSI on postId+createdAt is the primary access pattern
#    ("show all comments for post X in chronological order").
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "community_comments" {
  name         = "${var.environment}-CommunityComments"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "commentId"

  attribute {
    name = "commentId"
    type = "S"
  }
  attribute {
    name = "postId"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "postId-createdAt-index"
    hash_key        = "postId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-CommunityComments"
    Component = "community"
  }
}


# ----------------------------------------------------------------------------
# 8. CommunityPostInteractions
#    Per-user like/bookmark state on posts. Composite key (postId, userSub).
#    GSI on userSub for "show me everything I've liked or bookmarked".
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "community_post_interactions" {
  name         = "${var.environment}-CommunityPostInteractions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "postId"
  range_key    = "userSub"

  attribute {
    name = "postId"
    type = "S"
  }
  attribute {
    name = "userSub"
    type = "S"
  }

  global_secondary_index {
    name            = "userSub-postId-index"
    hash_key        = "userSub"
    range_key       = "postId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-CommunityPostInteractions"
    Component = "community"
  }
}


# ----------------------------------------------------------------------------
# 9. UserSharedFiles
#    Tracks which user-uploaded files are shared into community posts.
#    Composite key (userSub, fileKey).
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "user_shared_files" {
  name         = "${var.environment}-UserSharedFiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userSub"
  range_key    = "fileKey"

  attribute {
    name = "userSub"
    type = "S"
  }
  attribute {
    name = "fileKey"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "${var.environment}-UserSharedFiles"
    Component = "community"
  }
}


# ----------------------------------------------------------------------------
# 10. ProcessingSessions
#     Session state for async AI tasks (flashcards, summary, exam, etc.).
#     TTL on `expiresAt` automatically purges completed sessions after 7 days,
#     keeping the table small and read-fast.
#
#     Note: name uses suffix style (legacy) — preserved so app.py keeps working.
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "processing_sessions" {
  name         = "ProcessingSessions-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"

  attribute {
    name = "sessionId"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Name      = "ProcessingSessions-${var.environment}"
    Component = "ai-processing"
  }
}
