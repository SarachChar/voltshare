-- =============================================================================
-- Cron: expire-charger-promotions
-- -----------------------------------------------------------------------------
-- Flips ACTIVE promotions whose valid_until has passed to EXPIRED, so the app
-- (which only shows status = 'ACTIVE') stops showing them. Soft-deleted rows
-- are left untouched.
--
-- SCHEDULE
--   Every day at 00:00 Bangkok time (UTC+7). pg_cron schedules in UTC, so the
--   expression is 17:00 UTC: '0 17 * * *'.
--
-- HOW TO RUN
--   Run once in the SQL Editor after tables/charger_promotions.sql. Scheduling
--   a job with an existing name replaces it.
--
-- REMOVE
--   select cron.unschedule('expire-charger-promotions');
-- =============================================================================

select cron.schedule(
  'expire-charger-promotions',
  '0 17 * * *',
  $$
  update public.charger_promotions
  set status = 'EXPIRED',
      updated_at = now()
  where status = 'ACTIVE'
    and valid_until is not null
    and valid_until < now()
    and deleted_at is null;
  $$
);
