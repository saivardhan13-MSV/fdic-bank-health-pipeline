-- Adds derived metrics that need a bank's prior quarters: quarterly (not YTD) net
-- income, quarter-over-quarter and year-over-year growth, size bucket, funding mix.
-- Growth is computed only when the prior period really is the prior quarter/year, so
-- a bank with a gap in its filings doesn't get a bogus growth number.

with fin as (

    select * from {{ ref('stg_fdic__financials') }}

),

with_lags as (

    select
        fin.*,
        lag(report_date)            over (partition by cert order by report_date) as prev_report_date,
        lag(total_assets_usd)       over (partition by cert order by report_date) as prev_total_assets_usd,
        lag(total_deposits_usd)     over (partition by cert order by report_date) as prev_total_deposits_usd,
        lag(net_income_ytd_usd)     over (partition by cert order by report_date) as prev_net_income_ytd_usd,
        lag(report_date, 4)         over (partition by cert order by report_date) as yoy_report_date,
        lag(total_assets_usd, 4)    over (partition by cert order by report_date) as yoy_total_assets_usd,
        lag(total_deposits_usd, 4)  over (partition by cert order by report_date) as yoy_total_deposits_usd
    from fin

)

select
    financial_id,
    cert,
    report_date,
    {{ asset_size_bucket('total_assets_usd') }}                         as asset_size_bucket,

    total_assets_usd,
    total_deposits_usd,
    insured_deposits_usd,
    uninsured_deposits_usd,
    total_equity_usd,
    net_loans_usd,
    real_estate_loans_usd,
    securities_usd,
    cash_and_balances_usd,
    noncurrent_loans_usd,

    net_income_ytd_usd,
    -- YTD figures reset every January. Q1 = YTD; later quarters = YTD minus prior YTD.
    case
        when month(report_date) = 3 then net_income_ytd_usd
        when prev_report_date = last_day(dateadd(quarter, -1, report_date), 'quarter')
            then net_income_ytd_usd - prev_net_income_ytd_usd
    end                                                                 as net_income_qtd_usd,
    interest_income_ytd_usd,
    interest_expense_ytd_usd,
    noninterest_income_ytd_usd,
    noninterest_expense_ytd_usd,
    loan_loss_provision_ytd_usd,

    roa_pct,
    roe_pct,
    net_interest_margin_pct,
    efficiency_ratio_pct,
    tier1_leverage_ratio_pct,
    total_risk_based_capital_ratio_pct,
    noncurrent_loans_ratio_pct,
    net_charge_off_ratio_pct,
    loans_to_deposits_pct,

    round(100 * (total_equity_usd) / nullif(total_assets_usd, 0), 4)        as equity_to_assets_pct,
    round(100 * (cash_and_balances_usd + securities_usd) / nullif(total_assets_usd, 0), 4)
                                                                        as liquid_assets_to_assets_pct,
    -- Share of (insured + uninsured) deposits that is above the insurance limit.
    -- Post-SVB, a high share signals run risk.
    round(100 * (uninsured_deposits_usd) / nullif(insured_deposits_usd + uninsured_deposits_usd, 0), 4)
                                                                        as uninsured_deposit_share_pct,

    case when prev_report_date = last_day(dateadd(quarter, -1, report_date), 'quarter')
        then round(100 * (total_assets_usd - prev_total_assets_usd) / nullif(prev_total_assets_usd, 0), 4)
    end                                                                 as assets_qoq_growth_pct,
    case when yoy_report_date = last_day(dateadd(year, -1, report_date), 'quarter')
        then round(100 * (total_assets_usd - yoy_total_assets_usd) / nullif(yoy_total_assets_usd, 0), 4)
    end                                                                 as assets_yoy_growth_pct,
    case when yoy_report_date = last_day(dateadd(year, -1, report_date), 'quarter')
        then round(100 * (total_deposits_usd - yoy_total_deposits_usd) / nullif(yoy_total_deposits_usd, 0), 4)
    end                                                                 as deposits_yoy_growth_pct,

    _loaded_at
from with_lags
