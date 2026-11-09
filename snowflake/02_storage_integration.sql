-- =============================================================================
-- 02_storage_integration.sql: let Snowflake read the S3 raw bucket through an
-- IAM role (no AWS keys stored in Snowflake).
--
-- Order of operations (chicken-and-egg between AWS and Snowflake):
--   1. terraform apply  (creates the bucket + an IAM role with a placeholder trust)
--   2. run this file with the role ARN from `terraform output snowflake_role_arn`
--   3. DESC the integration; copy STORAGE_AWS_IAM_USER_ARN + STORAGE_AWS_EXTERNAL_ID
--      into terraform.tfvars and terraform apply again to lock the trust policy.
-- =============================================================================
use role accountadmin;

create storage integration if not exists s3_fdic_raw_int
  type = external_stage
  storage_provider = 'S3'
  enabled = true
  storage_aws_role_arn = '<snowflake_role_arn from terraform output>'
  storage_allowed_locations = ('s3://<raw_bucket from terraform output>/raw/fdic/');

desc integration s3_fdic_raw_int;   -- copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID

grant usage on integration s3_fdic_raw_int to role sysadmin;
grant usage on integration s3_fdic_raw_int to role fdic_loader;
