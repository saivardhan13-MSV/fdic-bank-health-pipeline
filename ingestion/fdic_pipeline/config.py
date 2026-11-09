"""Endpoint definitions for the FDIC BankFind Suite API (https://api.fdic.gov/banks).

Each endpoint lists the exact fields we pull. Pulling explicit fields (instead of
everything) keeps payloads small and makes schema drift visible: if the FDIC renames
a field, the value goes missing and the dbt not_null tests fail loudly.

Units: dollar amounts from /financials and /failures are reported in THOUSANDS of USD.
Ratios (ROA, NIMY, RBC1AAJ, ...) are percentages (1.25 == 1.25%).
"""

from __future__ import annotations

from dataclasses import dataclass

BASE_URL = "https://api.fdic.gov/banks"
PAGE_SIZE = 10_000  # API maximum for `limit`


@dataclass(frozen=True)
class Endpoint:
    name: str
    path: str
    fields: tuple[str, ...]
    sort_by: str
    # Financials are pulled one quarter (report date) at a time.
    partition_by_report_date: bool = False


INSTITUTIONS = Endpoint(
    name="institutions",
    path="institutions",
    fields=(
        "CERT",  # FDIC certificate number: the natural key for a bank
        "NAME",
        "CITY",
        "STALP",
        "STNAME",
        "ZIP",
        "CBSA",
        "ACTIVE",
        "INACTIVE",
        "BKCLASS",
        "REGAGNT",
        "FED_RSSD",
        "RSSDHCR",
        "NAMEHCR",
        "SPECGRPN",
        "OFFICES",
        "ASSET",
        "REPDTE",
        "ESTYMD",
        "ENDEFYMD",
        "DATEUPDT",
        "WEBADDR",
    ),
    sort_by="CERT",
)

FINANCIALS = Endpoint(
    name="financials",
    path="financials",
    fields=(
        "CERT",
        "REPDTE",
        # Identity as filed. ~80 non-insured trust companies file call reports but are
        # missing from /institutions, so the warehouse needs their name from here.
        "NAMEFULL",
        "CITY",
        "STALP",
        "BKCLASS",
        # Balance sheet ($000s)
        "ASSET",
        "DEP",
        "DEPINS",  # estimated insured deposits
        "DEPUNA",  # estimated uninsured deposits
        "EQ",
        "LNLSNET",
        "LNRE",
        "SC",
        "CHBAL",
        "NCLNLS",
        # Income statement, year-to-date ($000s)
        "NETINC",
        "INTINC",
        "EINTEXP",
        "NONII",
        "NONIX",
        "ELNATR",
        # Ratios (%)
        "ROA",
        "ROE",
        "NIMY",
        "EEFFR",
        "RBC1AAJ",
        "RBCRWAJ",
        "NCLNLSR",
        "NTLNLSR",
        "LNLSDEPR",
    ),
    sort_by="CERT",
    partition_by_report_date=True,
)

FAILURES = Endpoint(
    name="failures",
    path="failures",
    fields=(
        "CERT",
        "NAME",
        "CITYST",
        "PSTALP",
        "FAILDATE",
        "FAILYR",
        "SAVR",
        "RESTYPE",
        "RESTYPE1",
        "QBFASSET",
        "QBFDEP",
        "COST",
    ),
    sort_by="FAILDATE",
)

ENDPOINTS: dict[str, Endpoint] = {e.name: e for e in (INSTITUTIONS, FINANCIALS, FAILURES)}
