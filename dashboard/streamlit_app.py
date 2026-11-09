"""Bank health dashboard on top of the dbt marts.

Runs two ways:
  * Streamlit in Snowflake: paste this file in; it picks up the active session.
  * Locally:  pip install -r requirements.txt && streamlit run streamlit_app.py
             with SNOWFLAKE_ACCOUNT / SNOWFLAKE_USER / SNOWFLAKE_PRIVATE_KEY_PATH set.
"""

from __future__ import annotations

import os

import altair as alt
import pandas as pd
import streamlit as st

MARTS = os.environ.get("FDIC_MARTS_SCHEMA", "FDIC.MARTS")
TIER_ORDER = ["Strong", "Satisfactory", "Watch", "High Risk"]
TIER_COLORS = ["#2e7d32", "#7cb342", "#f9a825", "#c62828"]

st.set_page_config(page_title="Bank Health Monitor", layout="wide")


@st.cache_resource
def _session():
    try:  # Streamlit in Snowflake
        from snowflake.snowpark.context import get_active_session

        return get_active_session()
    except Exception:  # noqa: BLE001 - not inside Snowflake; fall back to a local session
        from snowflake.snowpark import Session

        return Session.builder.configs(
            {
                "account": os.environ["SNOWFLAKE_ACCOUNT"],
                "user": os.environ["SNOWFLAKE_USER"],
                "authenticator": "SNOWFLAKE_JWT",
                "private_key_file": os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
                "role": os.environ.get("SNOWFLAKE_ROLE", "FDIC_REPORTER"),
                "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "FDIC_WH"),
            }
        ).create()


@st.cache_data(ttl=3600)
def query(sql: str) -> pd.DataFrame:
    df = _session().sql(sql).to_pandas()
    df.columns = [c.lower() for c in df.columns]
    return df


st.title("Bank Health Monitor")
st.caption(
    "Source: FDIC BankFind Suite (public call report data). Scores compare each bank with "
    "peers of the same size in the same quarter. Analytical only, not a regulatory rating."
)

trends = query(f"select * from {MARTS}.industry_quarterly_trends order by report_date")
latest = query(f"select * from {MARTS}.bank_health_scorecard where is_latest_quarter")

if latest.empty:
    st.warning("No scorecard data yet. Run the pipeline first.")
    st.stop()

as_of = pd.to_datetime(latest["report_date"]).max().date()
reported = trends.dropna(subset=["reporting_banks"])
t_now = reported.iloc[-1]
t_prev = reported.iloc[-2] if len(reported) > 1 else t_now

# ------------------------------------------------------------------- KPIs
st.subheader(f"Industry snapshot, quarter ending {as_of:%b %d, %Y}")
k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Reporting banks", f"{int(t_now.reporting_banks):,}",
          f"{int(t_now.reporting_banks - t_prev.reporting_banks):+,}")
k2.metric("Total assets", f"${t_now.total_assets_usd / 1e12:,.2f}T")
k3.metric("Median ROA", f"{t_now.median_roa_pct:.2f}%",
          f"{t_now.median_roa_pct - t_prev.median_roa_pct:+.2f} pts")
k4.metric("Watch + High Risk", f"{int(t_now.banks_watch + t_now.banks_high_risk):,}",
          f"{int((t_now.banks_watch + t_now.banks_high_risk) - (t_prev.banks_watch + t_prev.banks_high_risk)):+,}",
          delta_color="inverse")
k5.metric("Failures this year",
          int(trends[pd.to_datetime(trends.report_date).dt.year == as_of.year].bank_failures.sum()))

tab_trends, tab_watch, tab_bank = st.tabs(["Industry trends", "Watch list", "Bank lookup"])

# ----------------------------------------------------------------- Trends
with tab_trends:
    t = trends.dropna(subset=["reporting_banks"]).copy()
    t["report_date"] = pd.to_datetime(t["report_date"])
    c1, c2 = st.columns(2)
    metric = c1.selectbox(
        "Metric",
        {
            "median_roa_pct": "Median ROA (%)",
            "median_net_interest_margin_pct": "Median net interest margin (%)",
            "median_tier1_leverage_ratio_pct": "Median tier 1 leverage (%)",
            "median_noncurrent_loans_ratio_pct": "Median noncurrent loans (%)",
            "median_uninsured_deposit_share_pct": "Median uninsured deposit share (%)",
        }.items(),
        format_func=lambda kv: kv[1],
    )
    c1.altair_chart(
        alt.Chart(t).mark_line(point=False).encode(
            x=alt.X("report_date:T", title=None),
            y=alt.Y(f"{metric[0]}:Q", title=metric[1]),
            tooltip=["quarter_label", alt.Tooltip(f"{metric[0]}:Q", format=".2f")],
        ),
        use_container_width=True,
    )
    tiers = t.melt(
        id_vars=["report_date"],
        value_vars=["banks_strong", "banks_satisfactory", "banks_watch", "banks_high_risk"],
        var_name="tier", value_name="banks",
    )
    tiers["tier"] = tiers["tier"].map(dict(zip(
        ["banks_strong", "banks_satisfactory", "banks_watch", "banks_high_risk"], TIER_ORDER, strict=True)))
    c2.markdown("**Banks by health tier**")
    c2.altair_chart(
        alt.Chart(tiers).mark_area().encode(
            x=alt.X("report_date:T", title=None),
            y=alt.Y("banks:Q", stack="normalize", title="Share of banks", axis=alt.Axis(format="%")),
            color=alt.Color("tier:N", sort=TIER_ORDER,
                            scale=alt.Scale(domain=TIER_ORDER, range=TIER_COLORS)),
            tooltip=["report_date:T", "tier:N", "banks:Q"],
        ),
        use_container_width=True,
    )
    st.markdown("**Bank failures per quarter**")
    st.altair_chart(
        alt.Chart(trends.assign(report_date=pd.to_datetime(trends.report_date))).mark_bar().encode(
            x=alt.X("report_date:T", title=None),
            y=alt.Y("bank_failures:Q", title="Failures"),
            tooltip=["quarter_label", "bank_failures", alt.Tooltip("failed_bank_assets_usd:Q", format="$,.0f")],
        ),
        use_container_width=True,
    )

# -------------------------------------------------------------- Watch list
with tab_watch:
    f1, f2, f3 = st.columns(3)
    tiers_pick = f1.multiselect("Tier", TIER_ORDER, default=["High Risk", "Watch"])
    buckets = sorted(latest["asset_size_bucket"].unique())
    bucket_pick = f2.multiselect("Size", buckets, default=buckets)
    states = ["All"] + sorted(latest["state_code"].dropna().unique())
    state_pick = f3.selectbox("State", states)
    w = latest[latest.health_tier.isin(tiers_pick) & latest.asset_size_bucket.isin(bucket_pick)]
    if state_pick != "All":
        w = w[w.state_code == state_pick]
    w = w.assign(newly_downgraded=w.prior_quarter_health_tier.isin(["Strong", "Satisfactory"]))
    st.caption(f"{len(w):,} banks · {int(w.newly_downgraded.sum()):,} newly downgraded this quarter")
    st.dataframe(
        w.sort_values(["risk_flag_count", "composite_score"], ascending=[False, True])[[
            "bank_name", "cert", "state_code", "asset_size_bucket", "health_tier",
            "prior_quarter_health_tier", "composite_score", "risk_flag_count",
            "tier1_leverage_ratio_pct", "noncurrent_loans_ratio_pct", "roa_pct",
            "loans_to_deposits_pct", "uninsured_deposit_share_pct",
        ]],
        hide_index=True, use_container_width=True,
        column_config={
            "composite_score": st.column_config.ProgressColumn("Score", min_value=0, max_value=100, format="%.0f"),
            "tier1_leverage_ratio_pct": st.column_config.NumberColumn("Tier 1 lev. %", format="%.2f"),
            "noncurrent_loans_ratio_pct": st.column_config.NumberColumn("Noncurrent %", format="%.2f"),
            "roa_pct": st.column_config.NumberColumn("ROA %", format="%.2f"),
            "loans_to_deposits_pct": st.column_config.NumberColumn("Loans/Dep %", format="%.1f"),
            "uninsured_deposit_share_pct": st.column_config.NumberColumn("Uninsured %", format="%.1f"),
        },
    )

# ------------------------------------------------------------- Bank lookup
with tab_bank:
    names = latest.sort_values("total_assets_usd", ascending=False)
    pick = st.selectbox(
        "Bank", names["cert"].tolist(),
        format_func=lambda c: f"{names.loc[names.cert == c, 'bank_name'].iloc[0]} (CERT {c})",
    )
    hist = query(
        f"select * from {MARTS}.bank_health_scorecard where cert = {int(pick)} order by report_date"
    )
    hist["report_date"] = pd.to_datetime(hist["report_date"])
    now = hist.iloc[-1]
    b1, b2, b3, b4 = st.columns(4)
    b1.metric("Health tier", now.health_tier, help=f"Prior quarter: {now.prior_quarter_health_tier}")
    b2.metric("Composite score", f"{now.composite_score:.0f} / 100")
    b3.metric("Total assets", f"${now.total_assets_usd / 1e9:,.2f}B")
    b4.metric("Peer group", now.asset_size_bucket, help=f"{int(now.peer_group_size):,} banks")
    flags = {
        "Tier 1 leverage < 5%": now.flag_low_capital,
        "Noncurrent loans > 3%": now.flag_high_noncurrent_loans,
        "Net charge-offs > 1%": now.flag_high_charge_offs,
        "Negative ROA": now.flag_unprofitable,
        "Loans / deposits > 100%": now.flag_high_loans_to_deposits,
        "Uninsured deposits > 50%": now.flag_high_uninsured_deposits,
    }
    raised = [k for k, v in flags.items() if v]
    st.write("**Risk flags:** " + (", ".join(raised) if raised else "none"))
    st.altair_chart(
        alt.Chart(hist).mark_line(point=True).encode(
            x=alt.X("report_date:T", title=None),
            y=alt.Y("composite_score:Q", title="Composite score", scale=alt.Scale(domain=[0, 100])),
            tooltip=["report_date:T", "health_tier", "composite_score"],
        ),
        use_container_width=True,
    )
