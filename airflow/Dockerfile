FROM astrocrpublic.azurecr.io/runtime:3.3-12

# dbt gets its own virtualenv: its dependencies conflict with Airflow's, so it must not
# share the Airflow environment. The DAG calls it via FDIC_DBT_BIN.
RUN python -m venv /usr/local/airflow/dbt_venv \
 && /usr/local/airflow/dbt_venv/bin/pip install --no-cache-dir "dbt-core>=1.9,<2" "dbt-snowflake>=1.9,<2"

ENV FDIC_DBT_BIN=/usr/local/airflow/dbt_venv/bin/dbt \
    FDIC_DBT_PROJECT_DIR=/usr/local/airflow/dbt \
    FDIC_DBT_PROFILES_DIR=/usr/local/airflow/include/dbt_profiles \
    FDIC_DBT_TARGET=prod
