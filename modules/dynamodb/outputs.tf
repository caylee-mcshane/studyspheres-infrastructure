###############################################################################
# Outputs — exposed so the compute module can scope its IAM policy precisely
# to these tables (least-privilege), and so future modules (e.g. Lambda
# consumers of the streams) can wire up cleanly.
###############################################################################

# Map of logical name -> table ARN. Useful for IAM policy resource lists.
output "table_arns" {
  description = "Map of logical names to DynamoDB table ARNs"
  value = {
    user_profiles               = aws_dynamodb_table.user_profiles.arn
    user_tokens                 = aws_dynamodb_table.user_tokens.arn
    promo_codes                 = aws_dynamodb_table.promo_codes.arn
    analytics_events            = aws_dynamodb_table.analytics_events.arn
    support_tickets             = aws_dynamodb_table.support_tickets.arn
    community_posts             = aws_dynamodb_table.community_posts.arn
    community_comments          = aws_dynamodb_table.community_comments.arn
    community_post_interactions = aws_dynamodb_table.community_post_interactions.arn
    user_shared_files           = aws_dynamodb_table.user_shared_files.arn
    processing_sessions         = aws_dynamodb_table.processing_sessions.arn
  }
}

# Flat list of all table ARNs PLUS all index ARNs — what an IAM policy needs
# to grant Query/Scan on indexes and CRUD on the base tables in one shot.
output "all_arns_for_iam" {
  description = "All table and GSI ARNs — pass directly into an IAM policy Resource list"
  value = concat(
    [
      aws_dynamodb_table.user_profiles.arn,
      aws_dynamodb_table.user_tokens.arn,
      aws_dynamodb_table.promo_codes.arn,
      aws_dynamodb_table.analytics_events.arn,
      aws_dynamodb_table.support_tickets.arn,
      aws_dynamodb_table.community_posts.arn,
      aws_dynamodb_table.community_comments.arn,
      aws_dynamodb_table.community_post_interactions.arn,
      aws_dynamodb_table.user_shared_files.arn,
      aws_dynamodb_table.processing_sessions.arn,
    ],
    [
      "${aws_dynamodb_table.user_profiles.arn}/index/*",
      "${aws_dynamodb_table.analytics_events.arn}/index/*",
      "${aws_dynamodb_table.support_tickets.arn}/index/*",
      "${aws_dynamodb_table.community_posts.arn}/index/*",
      "${aws_dynamodb_table.community_comments.arn}/index/*",
      "${aws_dynamodb_table.community_post_interactions.arn}/index/*",
    ],
  )
}

# Stream ARNs for tables with streams enabled — future Lambda event sources
# subscribe to these. Exposed even if you don't have consumers yet.
output "stream_arns" {
  description = "Stream ARNs for tables with streams enabled"
  value = {
    user_profiles    = aws_dynamodb_table.user_profiles.stream_arn
    analytics_events = aws_dynamodb_table.analytics_events.stream_arn
    community_posts  = aws_dynamodb_table.community_posts.stream_arn
  }
}

# Convenience: table name map. Useful if you ever want to inject names into
# EC2 user data or app config rather than hardcoding the prefix in app.py.
output "table_names" {
  description = "Map of logical names to actual table names"
  value = {
    user_profiles               = aws_dynamodb_table.user_profiles.name
    user_tokens                 = aws_dynamodb_table.user_tokens.name
    promo_codes                 = aws_dynamodb_table.promo_codes.name
    analytics_events            = aws_dynamodb_table.analytics_events.name
    support_tickets             = aws_dynamodb_table.support_tickets.name
    community_posts             = aws_dynamodb_table.community_posts.name
    community_comments          = aws_dynamodb_table.community_comments.name
    community_post_interactions = aws_dynamodb_table.community_post_interactions.name
    user_shared_files           = aws_dynamodb_table.user_shared_files.name
    processing_sessions         = aws_dynamodb_table.processing_sessions.name
  }
}
