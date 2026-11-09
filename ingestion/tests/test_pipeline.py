import gzip
import json
from datetime import date

import pytest

from fdic_pipeline import lambda_handler
from fdic_pipeline.client import FDICAPIError, FDICClient
from fdic_pipeline.config import FINANCIALS, INSTITUTIONS
from fdic_pipeline.extract import IncompleteExtractError, run_extract
from fdic_pipeline.quarters import (
    quarter_end_on_or_before,
    recent_report_dates,
    report_dates_between,
)
from fdic_pipeline.writer import LocalSink, build_key


class FakeClient(FDICClient):
    """Serves canned pages so tests never touch the network."""

    def __init__(self, records, total=None, page_size=2):
        super().__init__(page_size=page_size, backoff_seconds=0)
        self.records = records
        self.total = len(records) if total is None else total
        self.calls = []

    def _get(self, path, params):
        self.calls.append(params)
        start = params["offset"]
        page = self.records[start : start + params["limit"]]
        return {"meta": {"total": self.total}, "data": [{"data": r} for r in page]}


# ---------------------------------------------------------------- quarters
@pytest.mark.parametrize(
    "d, expected",
    [
        (date(2026, 11, 9), date(2026, 9, 30)),
        (date(2026, 9, 30), date(2026, 9, 30)),
        (date(2026, 1, 15), date(2025, 12, 31)),
        (date(2026, 3, 31), date(2026, 3, 31)),
    ],
)
def test_quarter_end_on_or_before(d, expected):
    assert quarter_end_on_or_before(d) == expected


def test_recent_report_dates_crosses_year_boundary():
    assert recent_report_dates(date(2026, 5, 1), 3) == ["20260331", "20251231", "20250930"]


def test_report_dates_between_is_oldest_first_and_complete():
    dates = report_dates_between(2025, date(2026, 7, 1))
    assert dates == ["20250331", "20250630", "20250930", "20251231", "20260331", "20260630"]


# ------------------------------------------------------------------ client
def test_client_follows_pagination():
    records = [{"CERT": i} for i in range(5)]
    client = FakeClient(records, page_size=2)
    got = list(client.iter_records(INSTITUTIONS))
    assert [r["CERT"] for r in got] == [0, 1, 2, 3, 4]
    assert [c["offset"] for c in client.calls] == [0, 2, 4]
    assert client.last_total == 5
    assert client.calls[0]["sort_by"] == "CERT"


def test_client_raises_on_api_errors():
    client = FakeClient([])
    client._get = lambda path, params: {"errors": [{"status": 400}]}
    with pytest.raises(FDICAPIError):
        list(client.iter_records(INSTITUTIONS))


# ------------------------------------------------------------ writer/extract
def test_build_key_layout():
    key = build_key("raw/fdic/", "financials", "2026-11-09", "scheduled__2026-11-09T10:00:00+00:00", "20260630")
    assert key == (
        "raw/fdic/financials/report_date=20260630/ingest_date=2026-11-09/"
        "scheduled__2026-11-09T10_00_00_00_00.ndjson.gz"
    )


def _read_ndjson_gz(path):
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        return [json.loads(line) for line in fh]


def test_extract_financials_writes_file_and_manifest_per_quarter(tmp_path):
    client = FakeClient([{"CERT": 1, "REPDTE": "20260630"}, {"CERT": 2, "REPDTE": "20260630"}])
    manifests = run_extract(
        "financials",
        LocalSink(tmp_path),
        run_id="test",
        report_dates=["20260630"],
        client=client,
    )
    assert len(manifests) == 1
    m = manifests[0]
    assert m.record_count == 2 and m.is_complete and m.report_date == "20260630"
    assert client.calls[0]["filters"] == "REPDTE:20260630"
    assert client.calls[0]["fields"] == ",".join(FINANCIALS.fields)

    lines = _read_ndjson_gz(tmp_path / m.key)
    assert lines[0]["data"] == {"CERT": 1, "REPDTE": "20260630"}
    assert lines[0]["_run_id"] == "test" and lines[0]["_endpoint"] == "financials"

    manifest_file = tmp_path / m.key.replace(".ndjson.gz", "._manifest.json")
    assert json.loads(manifest_file.read_text())["record_count"] == 2


def test_extract_skips_data_file_for_unpublished_quarter(tmp_path):
    manifests = run_extract(
        "financials", LocalSink(tmp_path), run_id="t", report_dates=["20260930"], client=FakeClient([])
    )
    assert manifests[0].record_count == 0
    assert not (tmp_path / manifests[0].key).exists()


def test_extract_fails_when_records_are_missing(tmp_path):
    client = FakeClient([{"CERT": 1}], total=3)  # API claims 3, serves 1
    with pytest.raises(IncompleteExtractError):
        run_extract("institutions", LocalSink(tmp_path), run_id="t", client=client)


def test_unknown_endpoint_rejected(tmp_path):
    with pytest.raises(ValueError):
        run_extract("nope", LocalSink(tmp_path), run_id="t")


# ------------------------------------------------------------------ lambda
def test_lambda_handler_uses_s3_sink(monkeypatch):
    puts = []

    class FakeS3:
        def put_object(self, **kw):
            puts.append(kw)

    monkeypatch.setenv("RAW_BUCKET", "test-bucket")
    monkeypatch.setattr("fdic_pipeline.writer.S3Sink.__init__", lambda self, bucket: (
        setattr(self, "bucket", bucket), setattr(self, "client", FakeS3())
    )[0])
    monkeypatch.setattr(
        "fdic_pipeline.extract.FDICClient", lambda: FakeClient([{"CERT": 9, "NAME": "Test Bank"}])
    )

    result = lambda_handler.handler({"endpoint": "institutions", "run_id": "r1"})
    assert result["total_records"] == 1
    assert {p["Bucket"] for p in puts} == {"test-bucket"}
    assert any(p["Key"].endswith(".ndjson.gz") for p in puts)
    assert all(p["ServerSideEncryption"] == "AES256" for p in puts)
