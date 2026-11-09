variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "raw_bucket_name" {
  description = "Globally unique S3 bucket name for the raw landing zone"
  type        = string
}

variable "raw_prefix" {
  type    = string
  default = "raw/fdic"
}

variable "lambda_function_name" {
  type    = string
  default = "fdic-extract"
}

variable "alert_email" {
  description = "Optional email for pipeline alerts (Lambda errors, Airflow failures). Empty = no subscription."
  type        = string
  default     = ""
}

# Filled in after creating the Snowflake storage integration (DESC INTEGRATION).
# Until then the role trusts only this AWS account, so Snowflake can't use it yet.
variable "snowflake_iam_user_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN from DESC INTEGRATION s3_fdic_raw_int"
  type        = string
  default     = ""
}

variable "snowflake_external_id" {
  description = "STORAGE_AWS_EXTERNAL_ID from DESC INTEGRATION s3_fdic_raw_int"
  type        = string
  default     = ""
}
