"""Write records as gzipped newline-delimited JSON, to S3 or a local folder.

Every line is an envelope:
    {"_run_id": ..., "_ingested_at": ..., "_endpoint": ..., "data": {...raw FDIC record...}}

Raw data is kept exactly as the API returned it. Typing and cleaning happen in dbt,
so a bad transformation can always be rebuilt from raw.

Each batch also gets a `_manifest.json` with the record count and the count the API
reported. The orchestrator uses it to confirm nothing was dropped.
"""

from __future__ import annotations

import gzip
import io
import json
import os
from collections.abc import Iterable
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Protocol


@dataclass
class Manifest:
    endpoint: str
    run_id: str
    ingested_at: str
    key: str
    record_count: int
    api_reported_total: int
    report_date: str | None = None

    @property
    def is_complete(self) -> bool:
        return self.record_count == self.api_reported_total


class Sink(Protocol):
    def put(self, key: str, body: bytes, content_type: str) -> str: ...


class LocalSink:
    def __init__(self, root: str | os.PathLike[str]) -> None:
        self.root = Path(root)

    def put(self, key: str, body: bytes, content_type: str) -> str:
        path = self.root / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
        return str(path)


class S3Sink:
    def __init__(self, bucket: str, client: Any | None = None) -> None:
        if client is None:
            import boto3  # available in the Lambda runtime; optional locally

            client = boto3.client("s3")
        self.bucket = bucket
        self.client = client

    def put(self, key: str, body: bytes, content_type: str) -> str:
        self.client.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=body,
            ContentType=content_type,
            ServerSideEncryption="AES256",
        )
        return f"s3://{self.bucket}/{key}"


def build_key(prefix: str, endpoint: str, ingest_date: str, run_id: str, report_date: str | None) -> str:
    """raw/fdic/<endpoint>/[report_date=YYYYMMDD/]ingest_date=YYYY-MM-DD/<run_id>.ndjson.gz"""
    parts = [prefix.strip("/"), endpoint]
    if report_date:
        parts.append(f"report_date={report_date}")
    parts.append(f"ingest_date={ingest_date}")
    safe_run = "".join(c if c.isalnum() or c in "-_." else "_" for c in run_id)
    return "/".join(parts) + f"/{safe_run}.ndjson.gz"


def write_batch(
    sink: Sink,
    records: Iterable[dict[str, Any]],
    *,
    key: str,
    endpoint: str,
    run_id: str,
    ingested_at: str,
    total_getter: Any,
    report_date: str | None = None,
) -> Manifest:
    """Stream records into one gzip NDJSON object, then write its manifest."""
    buf = io.BytesIO()
    count = 0
    with gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        for record in records:
            envelope = {
                "_run_id": run_id,
                "_ingested_at": ingested_at,
                "_endpoint": endpoint,
                "data": record,
            }
            gz.write(json.dumps(envelope, separators=(",", ":")).encode("utf-8") + b"\n")
            count += 1

    manifest = Manifest(
        endpoint=endpoint,
        run_id=run_id,
        ingested_at=ingested_at,
        key=key,
        record_count=count,
        api_reported_total=int(total_getter()),
        report_date=report_date,
    )
    # Write the data file only when it holds records (an unpublished quarter returns 0).
    if count:
        sink.put(key, buf.getvalue(), "application/x-ndjson")
    manifest_key = key.replace(".ndjson.gz", "._manifest.json")
    sink.put(manifest_key, json.dumps(asdict(manifest), indent=2).encode("utf-8"), "application/json")
    return manifest
