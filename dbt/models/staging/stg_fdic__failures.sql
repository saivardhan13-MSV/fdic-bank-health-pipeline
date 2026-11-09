-- One row per failure / assistance transaction. Keyed on the FDIC failure ID, not CERT:
-- about 500 older records have no CERT, and some CERTs appear more than once.

with source as (

    select * from {{ source('fdic_raw', 'fdic_failures') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by record:ID::varchar
        order by ingested_at desc, loaded_at desc, source_row
    ) = 1

)

select
    record:ID::number                                    as failure_id,
    record:CERT::number                                  as cert,
    trim(record:NAME::varchar)                           as bank_name,
    record:CITYST::varchar                               as city_state,
    record:PSTALP::varchar                               as state_code,
    {{ parse_mdy_date('record:FAILDATE') }}              as failure_date,
    record:FAILYR::number                                as failure_year,
    record:SAVR::varchar                                 as insurance_fund,
    record:RESTYPE::varchar                              as resolution_type,
    record:RESTYPE1::varchar                             as transaction_type,
    {{ thousands_to_usd('record:QBFASSET') }}            as total_assets_at_failure_usd,
    {{ thousands_to_usd('record:QBFDEP') }}              as total_deposits_at_failure_usd,
    {{ thousands_to_usd('record:COST') }}                as estimated_loss_usd,

    run_id                                               as _run_id,
    ingested_at                                          as _ingested_at,
    loaded_at                                            as _loaded_at
from latest
