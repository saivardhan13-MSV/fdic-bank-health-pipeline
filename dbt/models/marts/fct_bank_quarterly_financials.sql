{{
    config(
        materialized='incremental',
        unique_key=['cert', 'report_date'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        cluster_by=['report_date']
    )
}}

-- Fact table. Grain: one row per bank per quarter-end.
-- Incremental: each run re-merges the last N quarters (var incremental_lookback_quarters)
-- so amended call reports overwrite the earlier version instead of duplicating it.

select
    {{ dbt_utils.generate_surrogate_key(['e.cert']) }}           as bank_key,
    to_number(to_char(e.report_date, 'YYYYMMDD'))                as quarter_key,
    e.*
from {{ ref('int_financials__enriched') }} as e

{% if is_incremental() %}
where e.report_date >= (
    select dateadd(quarter, -{{ var('incremental_lookback_quarters') }}, max(report_date))
    from {{ this }}
)
{% endif %}
