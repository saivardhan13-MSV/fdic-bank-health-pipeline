{% docs __overview__ %}

# FDIC Bank Health Pipeline

Daily ELT pipeline on **real public data for every FDIC-insured U.S. bank**, from the
[FDIC BankFind API](https://api.fdic.gov/banks/docs/):

**FDIC API → AWS Lambda → S3 (raw NDJSON) → Snowflake (COPY INTO) → dbt → Airflow**

| | |
|---|---|
| Coverage | Q1 2015 to the latest quarter, ~4,300 banks per quarter, 240K+ bank-quarters |
| Reference data | 27,800+ institutions since 1934, 4,100+ failures |
| Tests | 79 dbt tests plus reconciliation and freshness controls |
| Orchestration | Airflow 3 DAG, daily at 11:00 UTC |

## Layers

| Layer | Models | What happens |
|---|---|---|
| **Sources** | `fdic_raw.*` | Untouched API JSON (`VARIANT`) with lineage columns: run ID, S3 file, row, load time |
| **Staging** | `stg_fdic__*` | Typed, deduped to the latest extract (`QUALIFY ROW_NUMBER()`), $000s → dollars, FDIC dates parsed |
| **Intermediate** | `int_financials__enriched` | Quarterly net income from YTD, QoQ / YoY growth (only when the prior quarter really exists), peer size bucket |
| **Marts** | `dim_bank`, `dim_bank_history`, `dim_quarter`, `fct_bank_quarterly_financials`, `fct_bank_failures` | Kimball star schema; incremental merge fact; SCD Type 2 bank history from a snapshot |
| **Analytics** | `bank_health_scorecard`, `industry_quarterly_trends` | CAMELS-style risk flags + 0-100 peer-percentile score and health tier; industry trends |

## Start here

- **`bank_health_scorecard`**: one row per bank per quarter. Six fixed-threshold risk
  flags (tier 1 leverage < 5%, noncurrent loans > 3%, net charge-offs > 1%, negative ROA,
  loans/deposits > 100%, uninsured deposits > 50%) plus a composite score from percentile
  ranks against same-size peers in the same quarter. Tiers: High Risk, Watch,
  Satisfactory, Strong. *Analytical only, not a regulatory rating.*
- **`industry_quarterly_trends`**: industry totals, medians, tier mix and failures per
  quarter. Shows the consolidation from ~6,400 reporting banks in 2015 to ~4,250 today,
  and the 2023 failures (Silicon Valley Bank, Signature, First Republic).

## Data quality notes

- **Inferred members.** About 80 non-insured trust companies file call reports but are
  missing from the FDIC institutions list. `dim_bank` adds them from their filings
  (`is_inferred_member = true`) instead of dropping their facts; the scorecard covers
  insured banks only.
- **Negative equity.** A few small banks report deposits above total assets. That's real
  (negative equity), so the units sanity test allows it and fails only on a likely
  $ vs $000s mix-up.
- Known outliers (tiny banks with extreme ratios) are `severity: warn` tests: visible,
  but they don't block the pipeline.

Source code: [github.com/saivardhan13-MSV/fdic-bank-health-pipeline](https://github.com/saivardhan13-MSV/fdic-bank-health-pipeline)

{% enddocs %}
