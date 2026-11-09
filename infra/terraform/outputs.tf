output "raw_bucket" {
  value = aws_s3_bucket.raw.id
}

output "raw_stage_url" {
  description = "Use as the Snowflake stage URL and the integration's allowed location"
  value       = "s3://${aws_s3_bucket.raw.id}/${var.raw_prefix}/"
}

output "lambda_function_name" {
  value = aws_lambda_function.extract.function_name
}

output "snowflake_role_arn" {
  description = "STORAGE_AWS_ROLE_ARN for the Snowflake storage integration"
  value       = aws_iam_role.snowflake.arn
}

output "snowflake_trust_configured" {
  value = local.snowflake_configured
}

output "airflow_policy_arn" {
  description = "Attach to the identity Airflow runs as"
  value       = aws_iam_policy.airflow.arn
}

output "alerts_topic_arn" {
  description = "Set as the Airflow Variable fdic_alert_sns_topic_arn"
  value       = aws_sns_topic.alerts.arn
}
