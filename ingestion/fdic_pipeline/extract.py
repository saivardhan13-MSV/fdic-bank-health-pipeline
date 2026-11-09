"""Extract orchestration shared by the Lambda handler and the local CLI."""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime

from .client import FDICClient
from .config import ENDPOINTS
from .quarters import recent_report_dates
from .writer import Manifest, Sink, build_key, write_batch

log = logging.getLogger(__name__)


class IncompleteExtractError(RuntimeError):
    pass


def run_extract(
    endpoint_name: str,
    sink: Sink,
    *,
    run_id: str,
    prefix: str = "raw/fdic",
    report_dates: list[str] | None = None,
    lookback_quarters: int = 4,
    today: date | None = None,
    client: FDICClient | None = None,
) -> list[Manifest]:
    """Pull one endpoint into the sink and return one manifest per file written.

    financials: one file per report date (explicit `report_dates`, or the last
    `lookback_quarters` quarter-ends). institutions / failures: one full snapshot.
    """
    if endpoint_name not in ENDPOINTS:
        raise ValueError(f"Unknown endpoint {endpoint_name!r}; choose from {sorted(ENDPOINTS)}")
    endpoint = ENDPOINTS[endpoint_name]
    client = client or FDICClient()
    now = datetime.now(UTC)
    ingested_at = now.isoformat(timespec="seconds")
    ingest_date = now.date().isoformat()

    batches: list[tuple[str | None, str | None]]  # (report_date, filter)
    if endpoint.partition_by_report_date:
        dates = report_dates or recent_report_dates(today or now.date(), lookback_quarters)
        batches = [(d, f"REPDTE:{d}") for d in dates]
    else:
        batches = [(None, None)]

    manifests = []
    for report_date, filters in batches:
        key = build_key(prefix, endpoint.name, ingest_date, run_id, report_date)
        manifest = write_batch(
            sink,
            client.iter_records(endpoint, filters=filters),
            key=key,
            endpoint=endpoint.name,
            run_id=run_id,
            ingested_at=ingested_at,
            total_getter=lambda: client.last_total,
            report_date=report_date,
        )
        log.info(
            "Wrote %s records (api total %s) to %s",
            manifest.record_count,
            manifest.api_reported_total,
            key,
        )
        if not manifest.is_complete:
            raise IncompleteExtractError(
                f"{endpoint.name} {report_date or ''}: wrote {manifest.record_count} records "
                f"but the API reported {manifest.api_reported_total}"
            )
        manifests.append(manifest)
    return manifests
