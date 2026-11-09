-- Bank dimension (type 1: current attributes). Full history of name, holding-company
-- and regulator changes lives in dim_bank_history (built from the dbt snapshot).
--
-- Inferred members: ~80 institutions (mostly non-insured trust companies) file call
-- reports but are missing from the FDIC /institutions endpoint. Rather than drop their
-- facts, they get a row here built from the identity fields on their latest filing,
-- flagged is_inferred_member = true (the Kimball late-arriving dimension pattern).

with institutions as (

    select * from {{ ref('stg_fdic__institutions') }}

),

charter as (

    select * from {{ ref('charter_classes') }}

),

failures as (

    -- Most recent failure / assistance event per bank (CERT can repeat).
    select *
    from {{ ref('stg_fdic__failures') }}
    where cert is not null
    qualify row_number() over (partition by cert order by failure_date desc, failure_id desc) = 1

),

inferred as (

    -- Latest filing per CERT that isn't in the institutions list; prefer rows with a name.
    select
        f.cert,
        f.reported_bank_name,
        f.reported_city,
        f.reported_state_code,
        f.reported_charter_class_code,
        f.total_assets_usd,
        f.report_date,
        f._loaded_at
    from {{ ref('stg_fdic__financials') }} as f
    left join institutions as i
        on f.cert = i.cert
    where i.cert is null
    qualify row_number() over (
        partition by f.cert
        order by (f.reported_bank_name is not null) desc, f.report_date desc
    ) = 1

),

unioned as (

    select
        cert,
        fed_rssd_id,
        bank_name,
        city,
        state_code,
        state_name,
        zip_code,
        metro_area,
        is_active,
        charter_class_code,
        primary_regulator,
        holding_company_rssd_id,
        holding_company_name,
        specialization,
        office_count,
        latest_total_assets_usd,
        latest_report_date,
        established_date,
        inactive_date,
        website,
        false                                            as is_inferred_member,
        _loaded_at
    from institutions

    union all

    select
        cert,
        null                                             as fed_rssd_id,
        coalesce(reported_bank_name, 'Unknown institution (CERT ' || cert || ')') as bank_name,
        reported_city                                    as city,
        reported_state_code                              as state_code,
        null                                             as state_name,
        null                                             as zip_code,
        null                                             as metro_area,
        true                                             as is_active,
        reported_charter_class_code                      as charter_class_code,
        null                                             as primary_regulator,
        null                                             as holding_company_rssd_id,
        null                                             as holding_company_name,
        null                                             as specialization,
        null                                             as office_count,
        total_assets_usd                                 as latest_total_assets_usd,
        report_date                                      as latest_report_date,
        null                                             as established_date,
        null                                             as inactive_date,
        null                                             as website,
        true                                             as is_inferred_member,
        _loaded_at
    from inferred

)

select
    {{ dbt_utils.generate_surrogate_key(['u.cert']) }}  as bank_key,
    u.cert,
    u.fed_rssd_id,
    u.bank_name,
    u.city,
    u.state_code,
    u.state_name,
    u.zip_code,
    u.metro_area,
    u.is_active,
    u.charter_class_code,
    coalesce(c.charter_class_description, 'Unknown')    as charter_class_description,
    coalesce(c.charter_type, 'Unknown')                 as charter_type,
    -- NC / NS charters are non-insured; unknown charters are treated as not insured.
    coalesce(u.charter_class_code not in ('NC', 'NS'), false)
        and not u.is_inferred_member                    as is_fdic_insured,
    u.primary_regulator,
    u.holding_company_rssd_id,
    u.holding_company_name,
    u.specialization,
    u.office_count,
    u.latest_total_assets_usd,
    u.latest_report_date,
    u.established_date,
    u.inactive_date,
    u.website,
    u.is_inferred_member,
    f.failure_id is not null                            as has_failure_record,
    f.failure_date                                      as last_failure_date,
    f.resolution_type                                   as last_resolution_type,
    u._loaded_at
from unioned as u
left join charter as c
    on u.charter_class_code = c.charter_class_code
left join failures as f
    on u.cert = f.cert
