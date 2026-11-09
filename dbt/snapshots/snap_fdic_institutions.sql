{#
  SCD type 2 history of bank attributes. Each daily run compares the current snapshot
  to the last version and closes or opens rows when these columns change: catches
  renames, holding-company acquisitions, charter conversions and closures.
#}
{% snapshot snap_fdic_institutions %}

{{
    config(
        target_schema='snapshots',
        unique_key='cert',
        strategy='check',
        check_cols=[
            'bank_name',
            'holding_company_name',
            'primary_regulator',
            'charter_class_code',
            'is_active',
            'state_code'
        ]
    )
}}

select
    cert,
    bank_name,
    holding_company_name,
    primary_regulator,
    charter_class_code,
    is_active,
    state_code
from {{ ref('stg_fdic__institutions') }}

{% endsnapshot %}
