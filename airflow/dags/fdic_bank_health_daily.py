"""
### FDIC bank health: daily pipeline

FDIC BankFind API -> **Lambda** -> **S3** (raw NDJSON) -> **Snowflake** (COPY INTO raw)
-> **dbt** (source freshness, then build: snapshot + models + tests).

| Task | What it does |
|---|---|
| `plan_extracts` | Decides which Lambda calls to make (normal day vs. backfill) |
| `invoke_extract` | One mapped task per call; fails if record counts don't reconcile |
| `copy_into_raw` | Loads new S3 files into `FDIC.RAW` (idempotent, skips loaded files) |
| `dbt_source_freshness` | Fails the run if raw data is stale |
| `dbt_build` | Snapshot, models and every dbt test, in dependency order |

**Backfill:** trigger manually with `{"backfill_start_year": 2010}`. Financials are
split into chunks of 8 quarters, each its own Lambda call, so no call hits the
15-minute Lambda limit.

Connections: `aws_default`, `snowflake_default`.
Variables: `fdic_lambda_function` (default `fdic-extract`), `fdic_alert_sns_topic_arn` (optional).
"""

from __future__ import annotations

import json
import logging
import os
from datetime import date, timedelta

import pendulum
from airflow.exceptions import AirflowException
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator

try:  # Airflow 3
    from airflow.providers.standard.operators.bash import BashOperator
    from airflow.sdk import Param, Variable, dag, task
except ImportError:  # Airflow 2.x
    from airflow.decorators import dag, task
    from airflow.models import Variable
    from airflow.models.param import Param
    from airflow.operators.bash import BashOperator

log = logging.getLogger(__name__)

DBT_BIN = os.environ.get("FDIC_DBT_BIN", "dbt")  # dbt lives in its own venv in the image
DBT_PROJECT_DIR = os.environ.get("FDIC_DBT_PROJECT_DIR", "/opt/airflow/dbt")
DBT_PROFILES_DIR = os.environ.get("FDIC_DBT_PROFILES_DIR", DBT_PROJECT_DIR)
DBT_TARGET = os.environ.get("FDIC_DBT_TARGET", "prod")
BACKFILL_CHUNK_QUARTERS = 8


def _variable(key: str, default: str | None = None) -> str | None:
    """Variable.get with a default that works on Airflow 2 and 3."""
    try:
        return Variable.get(key)
    except Exception:  # noqa: BLE001 - missing variable raises different types across versions
        return default


def _quarter_ends_since(start_year: int, today: date) -> list[str]:
    """Every quarter-end from start_year Q1 up to the last one on or before today (YYYYMMDD)."""
    out = []
    for year in range(start_year, today.year + 1):
        for month, day in ((3, 31), (6, 30), (9, 30), (12, 31)):
            q = date(year, month, day)
            if q <= today:
                out.append(q.strftime("%Y%m%d"))
    return out


def notify_failure(context) -> None:
    """Log the failure and, if a topic is configured, publish it to SNS (email/Slack/PagerDuty)."""
    ti = context["task_instance"]
    message = (
        f"FDIC pipeline failed: dag={ti.dag_id} task={ti.task_id} "
        f"run={context['run_id']} try={ti.try_number}\nLog: {getattr(ti, 'log_url', 'n/a')}"
    )
    log.error(message)
    topic_arn = _variable("fdic_alert_sns_topic_arn")
    if topic_arn:
        from airflow.providers.amazon.aws.hooks.sns import SnsHook

        SnsHook(aws_conn_id="aws_default").publish_to_target(
            target_arn=topic_arn, message=message, subject="FDIC pipeline failure"
        )


default_args = {
    "owner": "data-platform",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "on_failure_callback": notify_failure,
}


@dag(
    dag_id="fdic_bank_health_daily",
    description="FDIC BankFind -> S3 -> Snowflake -> dbt bank health marts",
    schedule="0 11 * * *",  # 11:00 UTC daily; FDIC refreshes its indexes overnight ET
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=3),
    default_args=default_args,
    doc_md=__doc__,
    tags=["fdic", "banking", "snowflake", "dbt"],
    params={
        "lookback_quarters": Param(4, type="integer", minimum=1, maximum=12,
                                   description="Recent quarters to re-pull (amended call reports)"),
        "backfill_start_year": Param(None, type=["null", "integer"], minimum=1992,
                                     description="Set to pull all quarters from this year onward"),
    },
)
def fdic_bank_health_daily():

    @task
    def plan_extracts(**context) -> list[dict]:
        params = context["params"]
        run_id = context["run_id"]
        payloads = [
            {"endpoint": "institutions", "run_id": run_id},
            {"endpoint": "failures", "run_id": run_id},
        ]
        start_year = params.get("backfill_start_year")
        if start_year:
            dates = _quarter_ends_since(int(start_year), pendulum.now("UTC").date())
            for i in range(0, len(dates), BACKFILL_CHUNK_QUARTERS):
                payloads.append(
                    {"endpoint": "financials", "run_id": run_id,
                     "report_dates": dates[i : i + BACKFILL_CHUNK_QUARTERS]}
                )
        else:
            payloads.append(
                {"endpoint": "financials", "run_id": run_id,
                 "lookback_quarters": int(params["lookback_quarters"])}
            )
        log.info("Planned %s extract calls", len(payloads))
        return payloads

    @task(retries=3, max_active_tis_per_dag=4)
    def invoke_extract(payload: dict) -> dict:
        from airflow.providers.amazon.aws.hooks.lambda_function import LambdaHook

        function_name = _variable("fdic_lambda_function", "fdic-extract")
        response = LambdaHook(aws_conn_id="aws_default").invoke_lambda(
            function_name=function_name,
            invocation_type="RequestResponse",
            payload=json.dumps(payload),
        )
        body = json.loads(response["Payload"].read())
        if response.get("FunctionError"):
            raise AirflowException(f"Lambda {function_name} failed for {payload}: {body}")

        # Reconciliation: each file's record count must match what the API reported.
        for f in body["files"]:
            if f["record_count"] != f["api_reported_total"]:
                raise AirflowException(f"Incomplete extract: {f}")
        log.info("%s: %s records in %s file(s)", body["endpoint"], body["total_records"], len(body["files"]))
        return {"endpoint": body["endpoint"], "total_records": body["total_records"], "files": len(body["files"])}

    @task
    def summarize_extracts(results: list[dict]) -> dict:
        totals: dict[str, int] = {}
        for r in results:
            totals[r["endpoint"]] = totals.get(r["endpoint"], 0) + r["total_records"]
        log.info("Extract totals: %s", totals)
        if totals.get("institutions", 0) == 0:
            raise AirflowException("Institutions snapshot came back empty; refusing to continue")
        return totals

    copy_into_raw = SQLExecuteQueryOperator(
        task_id="copy_into_raw",
        conn_id="snowflake_default",
        sql="sql/copy_into_raw.sql",
        split_statements=True,
        return_last=False,
    )

    dbt_env = {"DBT_PROFILES_DIR": DBT_PROFILES_DIR}
    dbt_source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && {DBT_BIN} deps --quiet"
            f" && {DBT_BIN} source freshness --target {DBT_TARGET}"
        ),
        env=dbt_env,
        append_env=True,
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        # `build` runs snapshot, seeds, models and tests in DAG order: a failing test
        # stops everything downstream of it from being published.
        bash_command=f"cd {DBT_PROJECT_DIR} && {DBT_BIN} build --target {DBT_TARGET}",
        env=dbt_env,
        append_env=True,
        execution_timeout=timedelta(hours=1),
    )

    planned = plan_extracts()
    results = invoke_extract.expand(payload=planned)
    summarize_extracts(results) >> copy_into_raw >> dbt_source_freshness >> dbt_build


fdic_bank_health_daily()
