-- Quarter dimension: one row per calendar quarter-end (the call report dates).

with spine as (

    {{ dbt_utils.date_spine(
        datepart="quarter",
        start_date="cast('" ~ var('history_start_date') ~ "' as date)",
        end_date="dateadd(quarter, 1, current_date())"
    ) }}

)

select
    to_number(to_char(last_day(date_quarter, 'quarter'), 'YYYYMMDD')) as quarter_key,
    last_day(date_quarter, 'quarter')                                 as report_date,
    date_quarter                                                      as quarter_start_date,
    year(date_quarter)                                                as calendar_year,
    quarter(date_quarter)                                             as calendar_quarter,
    year(date_quarter) || '-Q' || quarter(date_quarter)               as quarter_label,
    last_day(date_quarter, 'quarter') = last_day(date_quarter, 'year') as is_year_end
from spine
where last_day(date_quarter, 'quarter') <= current_date()
