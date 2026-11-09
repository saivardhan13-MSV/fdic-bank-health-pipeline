-- Reconciliation control: every distinct (bank, quarter) in the raw table must appear
-- exactly once in staging. Catches dedup bugs and records dropped by a bad cast.
-- Returns a row only when the counts differ.

with raw_keys as (
    select count(distinct record:CERT::number || '|' || record:REPDTE::varchar) as n
    from {{ source('fdic_raw', 'fdic_financials') }}
),

stg_keys as (
    select count(*) as n from {{ ref('stg_fdic__financials') }}
)

select raw_keys.n as raw_count, stg_keys.n as staging_count
from raw_keys cross join stg_keys
where raw_keys.n != stg_keys.n
