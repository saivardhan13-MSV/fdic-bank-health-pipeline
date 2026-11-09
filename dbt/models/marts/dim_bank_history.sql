-- Type 2 bank dimension: one row per version of a bank's attributes, from the snapshot.
-- Use it to answer "what was this bank called / who owned it as of date X?"

select
    {{ dbt_utils.generate_surrogate_key(['cert', 'dbt_valid_from']) }} as bank_version_key,
    {{ dbt_utils.generate_surrogate_key(['cert']) }}                   as bank_key,
    cert,
    bank_name,
    holding_company_name,
    primary_regulator,
    charter_class_code,
    is_active,
    state_code,
    dbt_valid_from                                                     as valid_from,
    dbt_valid_to                                                       as valid_to,
    dbt_valid_to is null                                               as is_current
from {{ ref('snap_fdic_institutions') }}
