{#
  prod: models land in the schema named in config (staging, marts, ...).
  dev / CI: everything is prefixed with the developer's schema (dbt_jane_marts) so
  people never overwrite each other or production.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
