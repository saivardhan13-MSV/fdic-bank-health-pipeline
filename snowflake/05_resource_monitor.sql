-- =============================================================================
-- 05_resource_monitor.sql: monthly credit cap on the pipeline warehouse.
-- Run once as ACCOUNTADMIN. Safe to re-run.
--
-- The daily pipeline uses a small fraction of a credit per day (X-Small warehouse,
-- 60-second auto-suspend), so 10 credits/month is generous. Past the cap the warehouse
-- suspends, so a runaway query or a forgotten loop can't drain the account.
--
-- Notifications go to account administrators who have a verified email in Snowsight:
-- your profile (bottom left) -> Settings -> Notifications -> email.
-- =============================================================================
use role accountadmin;

create or replace resource monitor fdic_monthly_cap
  with credit_quota = 10
       frequency = monthly
       start_timestamp = immediately
  triggers
    on 50 percent do notify
    on 80 percent do notify
    on 100 percent do suspend             -- let running queries finish, then suspend
    on 110 percent do suspend_immediate;  -- hard stop

alter warehouse fdic_wh set resource_monitor = fdic_monthly_cap;

show resource monitors like 'FDIC_MONTHLY_CAP';
