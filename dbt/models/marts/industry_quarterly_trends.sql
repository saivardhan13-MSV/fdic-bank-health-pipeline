-- Industry-wide trends. Grain: one row per quarter. Feeds the dashboard's trend charts.

with fin as (

    select * from {{ ref('bank_health_scorecard') }}

),

fin_rollup as (

    select
        report_date,
        count(*)                                                   as reporting_banks,
        sum(total_assets_usd)                                      as total_assets_usd,
        sum(total_deposits_usd)                                    as total_deposits_usd,
        median(roa_pct)                                            as median_roa_pct,
        median(net_interest_margin_pct)                            as median_net_interest_margin_pct,
        median(tier1_leverage_ratio_pct)                           as median_tier1_leverage_ratio_pct,
        median(noncurrent_loans_ratio_pct)                         as median_noncurrent_loans_ratio_pct,
        median(uninsured_deposit_share_pct)                        as median_uninsured_deposit_share_pct,
        count_if(health_tier = 'Strong')                           as banks_strong,
        count_if(health_tier = 'Satisfactory')                     as banks_satisfactory,
        count_if(health_tier = 'Watch')                            as banks_watch,
        count_if(health_tier = 'High Risk')                        as banks_high_risk,
        count_if(flag_unprofitable = 1)                            as banks_unprofitable
    from fin
    group by report_date

),

failure_rollup as (

    select
        quarter_key,
        count_if(resolution_type = 'FAILURE')                      as bank_failures,
        sum(iff(resolution_type = 'FAILURE', total_assets_at_failure_usd, 0)) as failed_bank_assets_usd,
        sum(iff(resolution_type = 'FAILURE', estimated_loss_usd, 0))          as failure_estimated_loss_usd
    from {{ ref('fct_bank_failures') }}
    group by quarter_key

)

select
    q.quarter_key,
    q.report_date,
    q.quarter_label,
    f.reporting_banks,
    f.total_assets_usd,
    f.total_deposits_usd,
    f.median_roa_pct,
    f.median_net_interest_margin_pct,
    f.median_tier1_leverage_ratio_pct,
    f.median_noncurrent_loans_ratio_pct,
    f.median_uninsured_deposit_share_pct,
    f.banks_strong,
    f.banks_satisfactory,
    f.banks_watch,
    f.banks_high_risk,
    f.banks_unprofitable,
    coalesce(fr.bank_failures, 0)                                  as bank_failures,
    coalesce(fr.failed_bank_assets_usd, 0)                         as failed_bank_assets_usd,
    coalesce(fr.failure_estimated_loss_usd, 0)                     as failure_estimated_loss_usd
from {{ ref('dim_quarter') }} as q
left join fin_rollup as f
    on q.report_date = f.report_date
left join failure_rollup as fr
    on q.quarter_key = fr.quarter_key
where f.report_date is not null or fr.quarter_key is not null
