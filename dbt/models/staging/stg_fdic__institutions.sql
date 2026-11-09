-- One row per institution (CERT), from the most recent snapshot that included it.

with source as (

    select * from {{ source('fdic_raw', 'fdic_institutions') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by record:CERT::number
        order by ingested_at desc, loaded_at desc, source_row
    ) = 1

)

select
    record:CERT::number                                  as cert,
    nullif(record:FED_RSSD::varchar, '')                 as fed_rssd_id,
    trim(record:NAME::varchar)                           as bank_name,
    trim(record:CITY::varchar)                           as city,
    record:STALP::varchar                                as state_code,
    record:STNAME::varchar                               as state_name,
    record:ZIP::varchar                                  as zip_code,
    nullif(record:CBSA::varchar, '')                     as metro_area,
    record:ACTIVE::number = 1                            as is_active,
    nullif(record:BKCLASS::varchar, '')                  as charter_class_code,
    record:REGAGNT::varchar                              as primary_regulator,
    nullif(record:RSSDHCR::varchar, '')                  as holding_company_rssd_id,
    nullif(trim(record:NAMEHCR::varchar), '')            as holding_company_name,
    nullif(record:SPECGRPN::varchar, '')                 as specialization,
    record:OFFICES::number                               as office_count,
    {{ thousands_to_usd('record:ASSET') }}               as latest_total_assets_usd,
    {{ parse_mdy_date('record:REPDTE') }}                as latest_report_date,
    {{ parse_mdy_date('record:ESTYMD') }}                as established_date,
    {{ parse_mdy_date('record:ENDEFYMD') }}              as inactive_date,
    {{ parse_mdy_date('record:DATEUPDT') }}              as fdic_last_updated_date,
    nullif(trim(record:WEBADDR::varchar), '')            as website,

    run_id                                               as _run_id,
    ingested_at                                          as _ingested_at,
    loaded_at                                            as _loaded_at
from latest
