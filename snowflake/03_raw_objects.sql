-- =============================================================================
-- 03_raw_objects.sql: file format, external stage and the raw landing tables.
--
-- Raw tables are append-only. Each row keeps the untouched API record in a VARIANT
-- plus lineage columns (which file, which row, which run). Staging models in dbt
-- dedupe and type the data, so raw can be replayed at any time.
-- =============================================================================
use role sysadmin;
use warehouse fdic_wh;
use schema fdic.raw;

create file format if not exists ff_ndjson_gz
  type = json
  compression = gzip
  strip_outer_array = false
  comment = 'Newline-delimited JSON, gzip (written by the ingestion Lambda)';

create stage if not exists stg_fdic_raw
  url = 's3://<raw_bucket from terraform output>/raw/fdic/'
  storage_integration = s3_fdic_raw_int
  file_format = ff_ndjson_gz;

grant usage on file format ff_ndjson_gz to role fdic_loader;
grant usage on stage stg_fdic_raw to role fdic_loader;

-- Same shape for every endpoint.
create table if not exists fdic_institutions (
  record        variant        not null comment 'Untouched FDIC API record',
  run_id        varchar        not null comment 'Airflow run / CLI run that extracted it',
  ingested_at   timestamp_tz   not null comment 'When the Lambda pulled it from the API',
  source_file   varchar        not null comment 'S3 key it was loaded from',
  source_row    number         not null comment 'Line number inside source_file',
  loaded_at     timestamp_tz   not null default current_timestamp() comment 'When COPY INTO loaded it'
);

create table if not exists fdic_financials like fdic_institutions;
create table if not exists fdic_failures   like fdic_institutions;

-- Hand ownership to the loader so it can COPY INTO.
grant insert, select on table fdic_institutions to role fdic_loader;
grant insert, select on table fdic_financials   to role fdic_loader;
grant insert, select on table fdic_failures     to role fdic_loader;
grant select on all tables in schema fdic.raw to role fdic_transformer;
