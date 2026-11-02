-- =============================================================================
-- Cron: expire-station-promotions
-- -----------------------------------------------------------------------------
-- Flips ACTIVE station promotions whose valid_until has passed to EXPIRED.
-- Same job as expire-charger-promotions, for the station_promotions table.
-- (expire-charger-promotions is unscheduled in Task 9 with its table.)
--
-- SCHEDULE
--   Every day at 00:00 Bangkok time (UTC+7) = 17:00 UTC: '0 17 * * *'.
--
-- HOW TO RUN
--   Run once in the SQL Editor after tables/station_promotions.sql.
--   Scheduling a job with an existing name replaces it.
--
-- REMOVE
--   select cron.unschedule('expire-station-promotions');
-- =============================================================================

select cron.schedule(
  'expire-station-promotions',
  '0 17 * * *',
  $$
  update public.station_promotions
  set status = 'EXPIRED'
  where status = 'ACTIVE'
    and valid_until is not null
    and valid_until < now()
    and deleted_at is null;
  $$
);
