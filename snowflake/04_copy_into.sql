-- =============================================================================
-- 04_copy_into.sql: load new files from S3 into the raw tables.
--
-- Airflow runs this every day (airflow/dags/sql/copy_into_raw.sql is the same
-- statements). COPY INTO keeps 64 days of load history per table, so files that were
-- already loaded are skipped automatically: re-running it is safe (idempotent).
-- Manifest files (*._manifest.json) are excluded by the PATTERN.
-- =============================================================================
use role fdic_loader;
use warehouse fdic_wh;
use schema fdic.raw;

copy into fdic_institutions (record, run_id, ingested_at, source_file, source_row)
from (
  select $1:data, $1:_run_id::varchar, $1:_ingested_at::timestamp_tz,
         metadata$filename, metadata$file_row_number
  from @stg_fdic_raw/institutions/
)
pattern = '.*[.]ndjson[.]gz'
on_error = abort_statement;

copy into fdic_financials (record, run_id, ingested_at, source_file, source_row)
from (
  select $1:data, $1:_run_id::varchar, $1:_ingested_at::timestamp_tz,
         metadata$filename, metadata$file_row_number
  from @stg_fdic_raw/financials/
)
pattern = '.*[.]ndjson[.]gz'
on_error = abort_statement;

copy into fdic_failures (record, run_id, ingested_at, source_file, source_row)
from (
  select $1:data, $1:_run_id::varchar, $1:_ingested_at::timestamp_tz,
         metadata$filename, metadata$file_row_number
  from @stg_fdic_raw/failures/
)
pattern = '.*[.]ndjson[.]gz'
on_error = abort_statement;

-- Quick check after a load
select 'institutions' as tbl, count(*) as rows, max(loaded_at) as last_load from fdic_institutions
union all select 'financials', count(*), max(loaded_at) from fdic_financials
union all select 'failures',   count(*), max(loaded_at) from fdic_failures;
