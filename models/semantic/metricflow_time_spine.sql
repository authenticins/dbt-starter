-- MetricFlow needs a daily date spine for time-based metrics.
with days as (

    {{ dbt.date_spine(
        datepart="day",
        start_date="to_date('" ~ var('time_spine_start') ~ "')",
        end_date="dateadd(year, 2, current_date)"
    ) }}

)

select cast(date_day as date) as date_day
from days
