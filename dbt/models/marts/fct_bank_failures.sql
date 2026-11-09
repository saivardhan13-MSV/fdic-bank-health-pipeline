-- Fact table. Grain: one row per failure or assistance transaction.

select
    f.failure_id,
    case when f.cert is not null
        then {{ dbt_utils.generate_surrogate_key(['f.cert']) }}
    end                                                              as bank_key,
    to_number(to_char(last_day(f.failure_date, 'quarter'), 'YYYYMMDD')) as quarter_key,
    f.cert,
    f.bank_name,
    f.city_state,
    f.state_code,
    f.failure_date,
    f.failure_year,
    f.insurance_fund,
    f.resolution_type,
    f.transaction_type,
    f.total_assets_at_failure_usd,
    f.total_deposits_at_failure_usd,
    f.estimated_loss_usd,
    round(100 * f.estimated_loss_usd / nullif(f.total_assets_at_failure_usd, 0), 2)
                                                                     as loss_to_assets_pct
from {{ ref('stg_fdic__failures') }} as f
