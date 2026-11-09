-- Same COPY statements as snowflake/04_copy_into.sql, run by the Airflow DAG.
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
