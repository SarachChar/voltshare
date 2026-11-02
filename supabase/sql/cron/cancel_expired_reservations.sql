-- =============================================================================
-- Cron: cancel-expired-reservations
-- -----------------------------------------------------------------------------
-- Cancels confirmed bookings the driver never started: if charging hasn't
-- begun (started_at is null) within 15 minutes of start_time, the booking is
-- set to 'cancelled', which also frees the slot (reservations_no_overlap only
-- applies to 'confirmed' rows). The booking fee is NOT refunded here.
--
-- SCHEDULE
--   At minute 15 and 45 of every hour: '15,45 * * * *'. Slots start on :00 /
--   :30, so each run lands exactly 15 minutes after a slot start.
--
-- HOW TO RUN
--   Run once in the SQL Editor after tables/reservations.sql. Scheduling a job
--   with an existing name replaces it.
--
-- REMOVE
--   select cron.unschedule('cancel-expired-reservations');
-- =============================================================================

select cron.schedule(
  'cancel-expired-reservations',
  '15,45 * * * *',
  $$
    update public.reservations
    set status = 'cancelled',
        updated_at = now()
    where status = 'confirmed'
      and started_at is null
      and start_time + interval '15 minutes' < now();
  $$
);
