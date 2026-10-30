-- =============================================================================
-- set_updated_at
-- -----------------------------------------------------------------------------
-- Trigger function that stamps `updated_at` with the current time whenever a
-- row is updated.
--
-- HOW TO RUN
--   Paste this whole file into the Supabase SQL Editor and run it once. It uses
--   CREATE OR REPLACE, so re-running it is safe. It must exist before the
--   triggers that call it are created.
--
-- USED BY (BEFORE UPDATE ... FOR EACH ROW triggers)
--   - booking_fee_set_updated_at        on public.booking_fee
--   - charger_businesses_set_updated_at on public.charger_businesses
--   - charger_promotions_set_updated_at on public.charger_promotions
--   - chargers_set_updated_at           on public.chargers
--   - charging_sessions_set_updated_at  on public.charging_sessions
--   - payment_methods_set_updated_at    on public.payment_methods
--   - profiles_set_updated_at           on public.profiles
--   - reservations_set_updated_at       on public.reservations
--   - reviews_set_updated_at            on public.reviews
--   - session_payments_set_updated_at   on public.session_payments
--
--   Tables without an updated_at column (business_images, charger_images,
--   charger_availability, session_streams) have no trigger.
--
-- NOTE
--   Only the function body was copied from the Supabase dashboard. The
--   signature (returns trigger, language plpgsql) is reconstructed, since
--   every trigger function must have that form.
-- =============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
