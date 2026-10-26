-- =============================================================================
-- Table: public.booking_fee
-- -----------------------------------------------------------------------------
-- Schema reference for the `booking_fee` table. Kept here for reference while
-- developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Records the booking fee charged when a reservation is made. One fee row per
--   reservation (enforced by a unique constraint on reservation_id).
--
-- RELATIONSHIPS
--   - reservation_id    -> reservations(id)     ON DELETE CASCADE
--   - payment_method_id -> payment_methods(id)  ON DELETE SET NULL
--
-- INDEXES
--   - booking_fee_reservation_idx on (reservation_id)
--
-- TRIGGERS
--   - booking_fee_set_updated_at: calls set_updated_at() BEFORE UPDATE to keep
--     updated_at current on every row change.
--
-- NOTES
--   - amount is in THB (baht). It's an integer because booking fees are always
--     whole baht; must be >= 0. Deducted from the charging bill
--     (session_payments.booking_fee_deducted) and never refunded.
--   - status is one of: 'paid', 'refunded' (default 'paid').
--   - refunded_at / refund_transaction_id: set by refund_booking_fee() when
--     the fee is refunded because the charger was unavailable at plug-in.
--     transaction_id keeps the original payment's id. Added with the ALTER
--     at the bottom of this file.
-- =============================================================================

create table public.booking_fee (
  id uuid not null default gen_random_uuid (),
  reservation_id uuid not null,
  payment_method_id uuid null,
  amount integer not null,
  status character varying(20) not null default 'paid'::character varying,
  transaction_id text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint booking_fee_pkey primary key (id),
  constraint booking_fee_reservation_id_key unique (reservation_id),
  constraint booking_fee_payment_method_id_fkey foreign KEY (payment_method_id) references payment_methods (id) on delete set null,
  constraint booking_fee_reservation_id_fkey foreign KEY (reservation_id) references reservations (id) on delete CASCADE,
  constraint booking_fee_amount_valid check ((amount >= 0)),
  constraint booking_fee_status_valid check (
    (
      (status)::text = any (
        (
          array[
            'paid'::character varying,
            'refunded'::character varying
          ]
        )::text[]
      )
    )
  )
) TABLESPACE pg_default;

create index IF not exists booking_fee_reservation_idx on public.booking_fee using btree (reservation_id) TABLESPACE pg_default;

create trigger booking_fee_set_updated_at BEFORE
update on booking_fee for EACH row
execute FUNCTION set_updated_at ();

-- -----------------------------------------------------------------------------
-- Refund fields (run once in the SQL Editor).
-- -----------------------------------------------------------------------------
alter table public.booking_fee
  add column if not exists refunded_at timestamp with time zone null,
  add column if not exists refund_transaction_id text null;
