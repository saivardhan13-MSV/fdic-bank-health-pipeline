{# Fails for any date that isn't a calendar quarter-end (Mar 31, Jun 30, Sep 30, Dec 31). #}
{% test is_quarter_end(model, column_name) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} != last_day({{ column_name }}, 'quarter')

{% endtest %}
