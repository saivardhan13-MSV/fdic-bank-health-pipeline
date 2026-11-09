# IAM role that Snowflake's storage integration assumes to read the raw bucket.
# Two-step setup (see snowflake/02_storage_integration.sql):
#   apply #1 -> role trusts only this account (placeholder)
#   create the integration in Snowflake, DESC it, set the two variables
#   apply #2 -> role trusts Snowflake's IAM user, locked to the external ID

data "aws_caller_identity" "current" {}

locals {
  snowflake_configured = var.snowflake_iam_user_arn != "" && var.snowflake_external_id != ""
}

data "aws_iam_policy_document" "snowflake_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "AWS"
      identifiers = [
        local.snowflake_configured
        ? var.snowflake_iam_user_arn
        : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
    dynamic "condition" {
      for_each = local.snowflake_configured ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.snowflake_external_id]
      }
    }
  }
}

resource "aws_iam_role" "snowflake" {
  name                 = "fdic-snowflake-s3-read"
  assume_role_policy   = data.aws_iam_policy_document.snowflake_assume.json
  max_session_duration = 3600
}

# Read-only, scoped to the raw prefix.
data "aws_iam_policy_document" "snowflake_read" {
  statement {
    sid       = "ReadObjects"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.raw.arn}/${var.raw_prefix}/*"]
  }
  statement {
    sid       = "ListPrefix"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.raw.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.raw_prefix}/*", "${var.raw_prefix}/"]
    }
  }
}

resource "aws_iam_role_policy" "snowflake_read" {
  name   = "read-raw"
  role   = aws_iam_role.snowflake.id
  policy = data.aws_iam_policy_document.snowflake_read.json
}
