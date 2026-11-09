"""Run extracts from your machine: for development, or for a one-time history backfill.

    python -m fdic_pipeline.cli extract institutions --local-dir ../data
    python -m fdic_pipeline.cli extract financials --lookback-quarters 2 --local-dir ../data
    python -m fdic_pipeline.cli backfill --start-year 2010 --bucket my-raw-bucket
"""

from __future__ import annotations

import argparse
import logging
import sys
import uuid
from datetime import date

from .config import ENDPOINTS
from .extract import run_extract
from .quarters import report_dates_between
from .writer import LocalSink, S3Sink, Sink


def _sink(args: argparse.Namespace) -> Sink:
    if args.bucket:
        return S3Sink(args.bucket)
    return LocalSink(args.local_dir)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="fdic_pipeline")
    sub = parser.add_subparsers(dest="command", required=True)

    def add_target(p: argparse.ArgumentParser) -> None:
        g = p.add_mutually_exclusive_group()
        g.add_argument("--bucket", help="Write to this S3 bucket")
        g.add_argument("--local-dir", default="./data", help="Write to a local folder (default)")
        p.add_argument("--prefix", default="raw/fdic")
        p.add_argument("--run-id", default=None)

    ex = sub.add_parser("extract", help="Pull one endpoint")
    ex.add_argument("endpoint", choices=sorted(ENDPOINTS))
    ex.add_argument("--lookback-quarters", type=int, default=4)
    ex.add_argument("--report-dates", nargs="*", help="Explicit YYYYMMDD report dates (financials)")
    add_target(ex)

    bf = sub.add_parser("backfill", help="Pull quarterly financials history")
    bf.add_argument("--start-year", type=int, required=True)
    add_target(bf)

    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    run_id = args.run_id or f"cli__{uuid.uuid4().hex[:12]}"
    sink = _sink(args)

    if args.command == "extract":
        manifests = run_extract(
            args.endpoint,
            sink,
            run_id=run_id,
            prefix=args.prefix,
            report_dates=args.report_dates,
            lookback_quarters=args.lookback_quarters,
        )
    else:
        dates = report_dates_between(args.start_year, date.today())
        manifests = run_extract("financials", sink, run_id=run_id, prefix=args.prefix, report_dates=dates)

    for m in manifests:
        print(f"{m.endpoint:<13} {m.report_date or '-':<9} {m.record_count:>7} records -> {m.key}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
