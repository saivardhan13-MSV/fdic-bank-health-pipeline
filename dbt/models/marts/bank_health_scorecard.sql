-- Bank health scorecard. Grain: one row per bank per quarter.
--
-- Loosely modeled on the CAMELS areas regulators use (Capital, Asset quality,
-- Earnings, Liquidity, Sensitivity/funding). Two layers:
--   1. Fixed-threshold risk flags, easy to explain ("tier 1 leverage below 5%").
--   2. A 0-100 composite score: the average of the bank's percentile rank against
--      peers of the same size in the same quarter. Percentiles shrug off the
--      extreme outliers tiny banks report.
-- This is an analytical view of public data, NOT a regulatory rating.

with base as (

    select
        f.bank_key,
        f.quarter_key,
        f.cert,
        f.report_date,
        f.asset_size_bucket,
        b.bank_name,
        b.state_code,
        b.holding_company_name,
        b.primary_regulator,
        f.total_assets_usd,
        f.total_deposits_usd,
        f.tier1_leverage_ratio_pct,
        f.total_risk_based_capital_ratio_pct,
        f.noncurrent_loans_ratio_pct,
        f.net_charge_off_ratio_pct,
        f.roa_pct,
        f.net_interest_margin_pct,
        f.efficiency_ratio_pct,
        f.loans_to_deposits_pct,
        f.uninsured_deposit_share_pct,
        f.deposits_yoy_growth_pct
    from {{ ref('fct_bank_quarterly_financials') }} as f
    inner join {{ ref('dim_bank') }} as b
        on f.bank_key = b.bank_key
    -- Score insured banks only: trust companies without deposits would skew the peer
    -- percentiles (and liquidity / funding metrics don't mean much for them).
    where b.is_fdic_insured

),

scored as (

    select
        base.*,

        -- Risk flags (1 = concern)
        iff(tier1_leverage_ratio_pct < 5, 1, 0)      as flag_low_capital,
        iff(noncurrent_loans_ratio_pct > 3, 1, 0)    as flag_high_noncurrent_loans,
        iff(net_charge_off_ratio_pct > 1, 1, 0)      as flag_high_charge_offs,
        iff(roa_pct < 0, 1, 0)                       as flag_unprofitable,
        iff(loans_to_deposits_pct > 100, 1, 0)       as flag_high_loans_to_deposits,
        iff(uninsured_deposit_share_pct > 50, 1, 0)  as flag_high_uninsured_deposits,

        -- Peer percentiles (1 = best in peer group)
        {{ peer_percentile('tier1_leverage_ratio_pct', higher_is_better=true) }}     as capital_pctl,
        {{ peer_percentile('noncurrent_loans_ratio_pct', higher_is_better=false) }}  as asset_quality_pctl,
        {{ peer_percentile('roa_pct', higher_is_better=true) }}                      as earnings_pctl,
        {{ peer_percentile('loans_to_deposits_pct', higher_is_better=false) }}       as liquidity_pctl,
        {{ peer_percentile('uninsured_deposit_share_pct', higher_is_better=false) }} as funding_pctl,

        count(*) over (partition by report_date, asset_size_bucket)                 as peer_group_size
    from base

),

composite as (

    select
        scored.*,
        flag_low_capital + flag_high_noncurrent_loans + flag_high_charge_offs
            + flag_unprofitable + flag_high_loans_to_deposits + flag_high_uninsured_deposits
                                                                    as risk_flag_count,
        round(100 * (
            coalesce(capital_pctl, 0) + coalesce(asset_quality_pctl, 0) + coalesce(earnings_pctl, 0)
            + coalesce(liquidity_pctl, 0) + coalesce(funding_pctl, 0)
        ) / nullif(
            iff(capital_pctl is null, 0, 1) + iff(asset_quality_pctl is null, 0, 1)
            + iff(earnings_pctl is null, 0, 1) + iff(liquidity_pctl is null, 0, 1)
            + iff(funding_pctl is null, 0, 1), 0
        ), 1)                                                       as composite_score
    from scored

),

tiered as (

    select
        composite.*,
        -- A relative score alone never makes a bank High Risk: that needs absolute flags.
        -- (Tested on Q2 2026: ~0.6% High Risk, ~22% Watch, ~27% Strong.)
        case
            when risk_flag_count >= 3
              or (risk_flag_count >= 2 and composite_score < 25)  then 'High Risk'
            when risk_flag_count >= 1 or composite_score < 20     then 'Watch'
            when composite_score >= 65                            then 'Strong'
            else 'Satisfactory'
        end                                                         as health_tier
    from composite

)

select
    tiered.*,
    lag(health_tier) over (partition by cert order by report_date)      as prior_quarter_health_tier,
    lag(composite_score) over (partition by cert order by report_date)  as prior_quarter_composite_score,
    report_date = max(report_date) over ()                              as is_latest_quarter
from tiered
