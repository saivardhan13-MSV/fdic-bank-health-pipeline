"""Small, dependency-free client for the FDIC BankFind Suite API.

Uses only the standard library so the Lambda deployment package is just our source
files (boto3 ships with the Lambda runtime).
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Iterator
from typing import Any

from .config import BASE_URL, PAGE_SIZE, Endpoint

log = logging.getLogger(__name__)

RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class FDICAPIError(RuntimeError):
    pass


class FDICClient:
    def __init__(
        self,
        base_url: str = BASE_URL,
        page_size: int = PAGE_SIZE,
        timeout: int = 60,
        max_retries: int = 5,
        backoff_seconds: float = 2.0,
        user_agent: str = "fdic-bank-health-pipeline/1.0",
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.page_size = page_size
        self.timeout = timeout
        self.max_retries = max_retries
        self.backoff_seconds = backoff_seconds
        self.user_agent = user_agent

    # ------------------------------------------------------------------ HTTP
    def _get(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}/{path}?{urllib.parse.urlencode(params)}"
        request = urllib.request.Request(
            url, headers={"Accept": "application/json", "User-Agent": self.user_agent}
        )
        for attempt in range(1, self.max_retries + 1):
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as exc:
                if exc.code not in RETRYABLE_STATUS or attempt == self.max_retries:
                    body = exc.read().decode("utf-8", errors="replace")[:500]
                    raise FDICAPIError(f"GET {url} failed: HTTP {exc.code}: {body}") from exc
                reason = f"HTTP {exc.code}"
            except (urllib.error.URLError, TimeoutError) as exc:
                if attempt == self.max_retries:
                    raise FDICAPIError(f"GET {url} failed: {exc}") from exc
                reason = str(exc)
            sleep_for = self.backoff_seconds * 2 ** (attempt - 1)
            log.warning("Retry %s/%s for %s in %.1fs (%s)", attempt, self.max_retries, path, sleep_for, reason)
            time.sleep(sleep_for)
        raise FDICAPIError(f"GET {url} failed after {self.max_retries} attempts")  # pragma: no cover

    # ------------------------------------------------------------- Paging
    def iter_records(
        self, endpoint: Endpoint, filters: str | None = None
    ) -> Iterator[dict[str, Any]]:
        """Yield every record for an endpoint, following offset pagination.

        After the last page, `self.last_total` holds the total the API reported, so the
        caller can check that it received every record.
        """
        offset = 0
        self.last_total = 0
        while True:
            params: dict[str, Any] = {
                "fields": ",".join(endpoint.fields),
                "sort_by": endpoint.sort_by,
                "sort_order": "ASC",
                "limit": self.page_size,
                "offset": offset,
                "format": "json",
            }
            if filters:
                params["filters"] = filters
            payload = self._get(endpoint.path, params)
            if "errors" in payload:
                raise FDICAPIError(f"{endpoint.path} returned errors: {payload['errors']}")

            total = int(payload.get("meta", {}).get("total", 0))
            self.last_total = total
            rows = payload.get("data", [])
            log.info("%s offset=%s got=%s total=%s", endpoint.name, offset, len(rows), total)
            for row in rows:
                yield row["data"]

            offset += len(rows)
            if not rows or offset >= total:
                return
