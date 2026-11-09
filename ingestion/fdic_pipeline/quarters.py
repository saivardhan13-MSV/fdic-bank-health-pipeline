"""Quarter-end (call report date) helpers. FDIC report dates look like '20260630'."""

from __future__ import annotations

from datetime import date

_QUARTER_ENDS = ((3, 31), (6, 30), (9, 30), (12, 31))


def quarter_end_on_or_before(d: date) -> date:
    for month, day in reversed(_QUARTER_ENDS):
        candidate = date(d.year, month, day)
        if candidate <= d:
            return candidate
    return date(d.year - 1, 12, 31)


def previous_quarter_end(q: date) -> date:
    idx = [(m, dd) for m, dd in _QUARTER_ENDS].index((q.month, q.day))
    if idx == 0:
        return date(q.year - 1, 12, 31)
    month, day = _QUARTER_ENDS[idx - 1]
    return date(q.year, month, day)


def recent_report_dates(today: date, lookback_quarters: int) -> list[str]:
    """The last N quarter-ends on or before `today`, newest first, as YYYYMMDD.

    Banks file call reports about 30 days after quarter end and can amend them, so a
    daily run re-pulls a few recent quarters. Downstream dedup keeps the latest copy.
    """
    if lookback_quarters < 1:
        raise ValueError("lookback_quarters must be >= 1")
    q = quarter_end_on_or_before(today)
    out = []
    for _ in range(lookback_quarters):
        out.append(q.strftime("%Y%m%d"))
        q = previous_quarter_end(q)
    return out


def report_dates_between(start_year: int, end: date) -> list[str]:
    """Every quarter-end from Q1 of start_year to the last quarter-end <= end, oldest first."""
    last = quarter_end_on_or_before(end)
    out = []
    q = last
    while q.year >= start_year:
        out.append(q.strftime("%Y%m%d"))
        q = previous_quarter_end(q)
    return list(reversed(out))
