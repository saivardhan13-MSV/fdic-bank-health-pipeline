# Extraction Lambda. The package is just our source: the code uses only the standard
# library, and boto3 ships with the runtime.

data "archive_file" "extract" {
  type        = "zip"
  source_dir  = "${path.module}/../../ingestion"
  output_path = "${path.module}/build/fdic_extract.zip"
  excludes = [
    "tests",
    "pyproject.toml",
    ".pytest_cache",
    ".ruff_cache",
    "fdic_pipeline/__pycache__",
  ]
}

resource "aws_cloudwatch_log_group" "extract" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 30
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "extract" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Least privilege: write only under the raw prefix, and log to its own log group.
data "aws_iam_policy_document" "extract" {
  statement {
    sid       = "WriteRaw"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.raw.arn}/${var.raw_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.extract.arn}:*"]
  }
}

resource "aws_iam_role_policy" "extract" {
  name   = "write-raw-and-logs"
  role   = aws_iam_role.extract.id
  policy = data.aws_iam_policy_document.extract.json
}

resource "aws_lambda_function" "extract" {
  function_name    = var.lambda_function_name
  description      = "Pull FDIC BankFind data into the S3 raw zone"
  role             = aws_iam_role.extract.arn
  runtime          = "python3.12"
  handler          = "fdic_pipeline.lambda_handler.handler"
  filename         = data.archive_file.extract.output_path
  source_code_hash = data.archive_file.extract.output_base64sha256
  timeout          = 900 # 15 min (Lambda max); backfills are chunked to fit
  memory_size      = 512
  architectures    = ["arm64"]

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw.id
      RAW_PREFIX = var.raw_prefix
      LOG_LEVEL  = "INFO"
    }
  }

  depends_on = [aws_cloudwatch_log_group.extract, aws_iam_role_policy.extract]
}

# ------------------------------------------------------------------ Alerting
resource "aws_sns_topic" "alerts" {
  name = "fdic-pipeline-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "extract_errors" {
  alarm_name          = "${var.lambda_function_name}-errors"
  alarm_description   = "FDIC extract Lambda raised an error"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.extract.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ------------------------------------------------------- Airflow permissions
# Attach this to whatever identity Airflow runs as (MWAA execution role, an EC2 role,
# or an IAM user for local Airflow).
data "aws_iam_policy_document" "airflow" {
  statement {
    sid       = "InvokeExtract"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.extract.arn]
  }
  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_policy" "airflow" {
  name   = "fdic-airflow-orchestration"
  policy = data.aws_iam_policy_document.airflow.json
}
