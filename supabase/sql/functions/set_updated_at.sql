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
--   - booking_fee_set_updated_at      on public.booking_fee
--   - payment_methods_set_updated_at  on public.payment_methods
--   - reservations_set_updated_at     on public.reservations
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
