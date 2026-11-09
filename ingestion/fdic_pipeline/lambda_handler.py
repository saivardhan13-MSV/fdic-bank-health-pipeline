"""AWS Lambda entry point.

Event examples:
    {"endpoint": "institutions", "run_id": "scheduled__2026-11-09"}
    {"endpoint": "financials", "lookback_quarters": 4}
    {"endpoint": "financials", "report_dates": ["20100331", "20100630"]}   # backfill chunk

Environment:
    RAW_BUCKET   S3 bucket for the raw landing zone (required)
    RAW_PREFIX   key prefix, default "raw/fdic"
"""

from __future__ import annotations

import logging
import os
import uuid
from dataclasses import asdict
from typing import Any

from .extract import run_extract
from .writer import S3Sink

logging.getLogger().setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def handler(event: dict[str, Any], context: Any = None) -> dict[str, Any]:
    endpoint = event["endpoint"]
    run_id = event.get("run_id") or f"manual__{uuid.uuid4().hex[:12]}"
    sink = S3Sink(bucket=os.environ["RAW_BUCKET"])

    manifests = run_extract(
        endpoint,
        sink,
        run_id=run_id,
        prefix=os.environ.get("RAW_PREFIX", "raw/fdic"),
        report_dates=event.get("report_dates"),
        lookback_quarters=int(event.get("lookback_quarters", 4)),
    )
    return {
        "endpoint": endpoint,
        "run_id": run_id,
        "files": [asdict(m) for m in manifests],
        "total_records": sum(m.record_count for m in manifests),
    }
