-- =============================================================================
-- 01_setup.sql: warehouse, database, schemas and least-privilege roles.
-- Run once as ACCOUNTADMIN (or SYSADMIN + SECURITYADMIN).
-- =============================================================================
use role accountadmin;

-- One small warehouse that suspends quickly keeps a trial account cheap.
create warehouse if not exists fdic_wh
  warehouse_size = 'XSMALL'
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true
  comment = 'FDIC bank health pipeline';

create database if not exists fdic comment = 'FDIC BankFind data: raw landing + dbt models';
create schema if not exists fdic.raw comment = 'Append-only raw JSON loaded from S3. Never edited by hand.';

-- SYSADMIN owns the database objects (ACCOUNTADMIN owns as little as possible).
grant ownership on database fdic to role sysadmin copy current grants;
grant ownership on schema fdic.raw to role sysadmin copy current grants;
grant ownership on warehouse fdic_wh to role sysadmin copy current grants;
-- dbt creates fdic.staging, fdic.intermediate, fdic.marts and fdic.snapshots.

-- ----------------------------------------------------------------- Roles
-- FDIC_LOADER      : Airflow COPY INTO raw tables
-- FDIC_TRANSFORMER : dbt builds everything outside RAW, reads RAW
-- FDIC_REPORTER    : dashboards / analysts, read-only on marts
create role if not exists fdic_loader;
create role if not exists fdic_transformer;
create role if not exists fdic_reporter;
grant role fdic_loader to role sysadmin;
grant role fdic_transformer to role sysadmin;
grant role fdic_reporter to role fdic_transformer;

grant usage on warehouse fdic_wh to role fdic_loader;
grant usage on warehouse fdic_wh to role fdic_transformer;
grant usage on warehouse fdic_wh to role fdic_reporter;

grant usage on database fdic to role fdic_loader;
grant usage on database fdic to role fdic_transformer;
grant usage on database fdic to role fdic_reporter;

-- Loader: write raw only
grant usage on schema fdic.raw to role fdic_loader;
grant insert, select on future tables in schema fdic.raw to role fdic_loader;

-- Transformer: read raw, create its own schemas
grant usage on schema fdic.raw to role fdic_transformer;
grant select on future tables in schema fdic.raw to role fdic_transformer;
grant create schema on database fdic to role fdic_transformer;

-- Reporter: read marts (dbt grants per-model via the `grants` config as well)
grant usage on future schemas in database fdic to role fdic_reporter;
grant select on future tables in database fdic to role fdic_reporter;
grant select on future views in database fdic to role fdic_reporter;

-- ----------------------------------------------------------------- Service users
-- Key-pair auth for service users (no passwords). Generate keys with:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
--   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
create user if not exists svc_fdic_airflow
  type = service
  default_role = fdic_loader
  default_warehouse = fdic_wh
  comment = 'Airflow: COPY INTO raw + runs dbt';
-- alter user svc_fdic_airflow set rsa_public_key = '<contents of rsa_key.pub without header/footer>';
grant role fdic_loader to user svc_fdic_airflow;
grant role fdic_transformer to user svc_fdic_airflow;
