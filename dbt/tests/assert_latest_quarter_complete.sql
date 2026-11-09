{{ config(severity='warn') }}

-- Completeness check: the newest quarter should have roughly as many reporting banks
-- as the one before it. A drop of over 5% means a partial extract or a quarter still
-- being published. Warn instead of fail, since early in a filing season this is expected.

with counts as (
    select report_date, count(*) as banks
    from {{ ref('fct_bank_quarterly_financials') }}
    group by report_date
),

ranked as (
    select report_date, banks, lag(banks) over (order by report_date) as prior_banks
    from counts
    qualify row_number() over (order by report_date desc) = 1
)

select *
from ranked
where banks < 0.95 * prior_banks
