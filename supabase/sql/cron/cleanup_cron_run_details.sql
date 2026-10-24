-- =============================================================================
-- Cron: cleanup-cron-run-details
-- -----------------------------------------------------------------------------
-- pg_cron writes one row to cron.job_run_details for every run of every job
-- (mock-charger-tick alone adds ~2,880 rows/day) and never prunes them. This
-- job deletes run logs older than 1 day, keeping the last 24 hours for
-- debugging.
--
-- SCHEDULE
--   Every day at 23:59 Bangkok time (UTC+7). pg_cron schedules in UTC, so the
--   expression is 16:59 UTC: '59 16 * * *'.
--
-- HOW TO RUN
--   Run once in the SQL Editor. Scheduling a job with an existing name
--   replaces it.
--
-- REMOVE
--   select cron.unschedule('cleanup-cron-run-details');
-- =============================================================================

select cron.schedule(
  'cleanup-cron-run-details',
  '59 16 * * *',
  $$ delete from cron.job_run_details where end_time < now() - interval '1 day' $$
);
