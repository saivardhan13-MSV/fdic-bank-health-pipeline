-- One row per bank per quarter. If a quarter was extracted more than once (daily
-- runs re-pull recent quarters to pick up amended call reports), keep the latest.

with source as (

    select * from {{ source('fdic_raw', 'fdic_financials') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by record:CERT::number, record:REPDTE::varchar
        order by ingested_at desc, loaded_at desc, source_row
    ) = 1

)

select
    record:ID::varchar                                   as financial_id,
    record:CERT::number                                  as cert,
    to_date(record:REPDTE::varchar, 'YYYYMMDD')          as report_date,

    -- Identity as filed (null in files extracted before these fields were added)
    nullif(trim(record:NAMEFULL::varchar), '')           as reported_bank_name,
    nullif(trim(record:CITY::varchar), '')               as reported_city,
    nullif(record:STALP::varchar, '')                    as reported_state_code,
    nullif(record:BKCLASS::varchar, '')                  as reported_charter_class_code,

    -- Balance sheet (whole USD)
    {{ thousands_to_usd('record:ASSET') }}               as total_assets_usd,
    {{ thousands_to_usd('record:DEP') }}                 as total_deposits_usd,
    {{ thousands_to_usd('record:DEPINS') }}              as insured_deposits_usd,
    {{ thousands_to_usd('record:DEPUNA') }}              as uninsured_deposits_usd,
    {{ thousands_to_usd('record:EQ') }}                  as total_equity_usd,
    {{ thousands_to_usd('record:LNLSNET') }}             as net_loans_usd,
    {{ thousands_to_usd('record:LNRE') }}                as real_estate_loans_usd,
    {{ thousands_to_usd('record:SC') }}                  as securities_usd,
    {{ thousands_to_usd('record:CHBAL') }}               as cash_and_balances_usd,
    {{ thousands_to_usd('record:NCLNLS') }}              as noncurrent_loans_usd,

    -- Income statement, year-to-date (whole USD)
    {{ thousands_to_usd('record:NETINC') }}              as net_income_ytd_usd,
    {{ thousands_to_usd('record:INTINC') }}              as interest_income_ytd_usd,
    {{ thousands_to_usd('record:EINTEXP') }}             as interest_expense_ytd_usd,
    {{ thousands_to_usd('record:NONII') }}               as noninterest_income_ytd_usd,
    {{ thousands_to_usd('record:NONIX') }}               as noninterest_expense_ytd_usd,
    {{ thousands_to_usd('record:ELNATR') }}              as loan_loss_provision_ytd_usd,

    -- Ratios as reported by the FDIC (percent, annualized where applicable)
    record:ROA::float                                    as roa_pct,
    record:ROE::float                                    as roe_pct,
    record:NIMY::float                                   as net_interest_margin_pct,
    record:EEFFR::float                                  as efficiency_ratio_pct,
    record:RBC1AAJ::float                                as tier1_leverage_ratio_pct,
    record:RBCRWAJ::float                                as total_risk_based_capital_ratio_pct,
    record:NCLNLSR::float                                as noncurrent_loans_ratio_pct,
    record:NTLNLSR::float                                as net_charge_off_ratio_pct,
    record:LNLSDEPR::float                               as loans_to_deposits_pct,

    run_id                                               as _run_id,
    ingested_at                                          as _ingested_at,
    loaded_at                                            as _loaded_at
from latest
