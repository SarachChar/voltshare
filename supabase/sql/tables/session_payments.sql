-- =============================================================================
-- Table: public.session_payments
-- -----------------------------------------------------------------------------
-- PURPOSE
--   The bill for a finished charging session. Created (as 'unpaid') when the
--   session stops; set to 'paid' / 'failed' by the pay-charging-session edge
--   function. One payment per session.
--
-- RELATIONSHIPS
--   - session_id        -> charging_sessions(id)  ON DELETE CASCADE  (unique)
--   - payment_method_id -> payment_methods(id)    ON DELETE SET NULL
--
-- TRIGGERS
--   - session_payments_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- AMOUNTS (THB, numeric(10,2))
--   - energy_amount        = round(total_energy_kwh * price_per_kwh_at_start, 2)
--   - booking_fee_deducted = booking_fee.amount of the reservation (0 if none)
--   - total_amount         = greatest(energy_amount - booking_fee_deducted, 0)
--                            -> the amount actually charged to the card.
--                            The booking fee is never refunded.
--   - platform_amount      = round(total_amount * 0.15, 2)
--   - host_amount          = total_amount - platform_amount
--   When total_amount is 0 the row is created already 'paid'.
--
-- NOTES
--   - status: 'unpaid' | 'paid' | 'failed'. 'failed' means the last attempt was
--     declined; the driver can retry (possibly with another card).
--   - transaction_id is the id returned by the mock card charge.
-- =============================================================================

create table public.session_payments (
  id uuid not null default gen_random_uuid (),
  session_id uuid not null,
  payment_method_id uuid null,
  energy_amount numeric(10, 2) not null,
  booking_fee_deducted numeric(10, 2) not null default 0,
  total_amount numeric(10, 2) not null,
  platform_amount numeric(10, 2) not null,
  host_amount numeric(10, 2) not null,
  status character varying(20) not null default 'unpaid'::character varying,
  transaction_id text null,
  paid_at timestamp with time zone null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint session_payments_pkey primary key (id),
  constraint session_payments_session_id_key unique (session_id),
  constraint session_payments_session_id_fkey foreign key (session_id)
    references charging_sessions (id) on delete cascade,
  constraint session_payments_payment_method_id_fkey foreign key (payment_method_id)
    references payment_methods (id) on delete set null,
  constraint session_payments_status_valid check (
    (status)::text = any (array['unpaid', 'paid', 'failed']::text[])
  ),
  constraint session_payments_amounts_valid check (
    energy_amount >= 0
    and booking_fee_deducted >= 0
    and total_amount >= 0
    and platform_amount >= 0
    and host_amount >= 0
    and platform_amount + host_amount = total_amount
  )
) tablespace pg_default;

create trigger session_payments_set_updated_at before
update on session_payments for each row
execute function set_updated_at ();
