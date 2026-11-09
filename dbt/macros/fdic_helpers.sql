{#
  FDIC dates come as 'M/D/YYYY' or 'MM/DD/YYYY' strings. Splitting on '/' handles both
  forms and returns null for blanks or junk instead of failing the whole model.
  The sentinel 12/31/9999 ("no end date") becomes null.
#}
{% macro parse_mdy_date(expr) -%}
    case
        when nullif(trim({{ expr }}::varchar), '') is null then null
        when {{ expr }}::varchar = '12/31/9999' then null
        else date_from_parts(
            try_to_number(split_part({{ expr }}::varchar, '/', 3)),
            try_to_number(split_part({{ expr }}::varchar, '/', 1)),
            try_to_number(split_part({{ expr }}::varchar, '/', 2))
        )
    end
{%- endmacro %}


{# FDIC dollar amounts are in thousands (some failure amounts have decimals). Convert to whole dollars. #}
{% macro thousands_to_usd(expr) -%}
    ({{ expr }}::number(38, 3) * 1000)::number(38, 0)
{%- endmacro %}


{# FDIC peer groups by total assets (in whole dollars). #}
{% macro asset_size_bucket(total_assets_usd) -%}
    case
        when {{ total_assets_usd }} is null then 'Unknown'
        when {{ total_assets_usd }} <  100000000      then '1. Under $100M'
        when {{ total_assets_usd }} <  1000000000     then '2. $100M - $1B'
        when {{ total_assets_usd }} <  10000000000    then '3. $1B - $10B'
        when {{ total_assets_usd }} <  100000000000   then '4. $10B - $100B'
        else '5. Over $100B'
    end
{%- endmacro %}


{#
  Percentile of a metric among peers in the same quarter and size bucket (0 = worst,
  1 = best). Nulls get no percentile instead of being ranked last.
#}
{% macro peer_percentile(metric, higher_is_better=true) -%}
    case when {{ metric }} is null then null else
        {% if higher_is_better %}
        percent_rank() over (
            partition by report_date, asset_size_bucket, ({{ metric }} is null)
            order by {{ metric }}
        )
        {% else %}
        1 - percent_rank() over (
            partition by report_date, asset_size_bucket, ({{ metric }} is null)
            order by {{ metric }}
        )
        {% endif %}
    end
{%- endmacro %}
