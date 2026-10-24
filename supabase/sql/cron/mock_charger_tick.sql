-- =============================================================================
-- Cron: mock-charger-tick
-- -----------------------------------------------------------------------------
-- Every 30 seconds, ask the mock charger to report MeterValues for every
-- session that is charging (see functions/trigger_mock_charger.sql).
--
-- HOW TO RUN
--   Run once in the SQL Editor after trigger_mock_charger.sql. Scheduling a job
--   with an existing name replaces it.
--
-- PAUSE / REMOVE
--   select cron.unschedule('mock-charger-tick');
-- =============================================================================

select cron.schedule(
  'mock-charger-tick',
  '30 seconds',
  $$ select public.trigger_mock_charger(); $$
);
