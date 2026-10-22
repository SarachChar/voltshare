-- =============================================================================
-- Table: public.payment_methods
-- -----------------------------------------------------------------------------
-- Schema reference for the `payment_methods` table. Kept here for reference
-- while developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Stores a user's saved payment cards. Referenced by booking_fee via
--   payment_method_id.
--
-- RELATIONSHIPS
--   - user_id -> profiles(id)  ON DELETE CASCADE
--
-- INDEXES
--   - payment_methods_user_idx on (user_id)
--   - payment_methods_one_default_idx: PARTIAL UNIQUE index on (user_id) WHERE
--     is_default = true. Guarantees at most one default card per user.
--
-- TRIGGERS
--   - payment_methods_set_updated_at: calls set_updated_at() BEFORE UPDATE to
--     keep updated_at current on every row change.
--
-- NOTES
--   - exp_month must be 1-12; exp_year must be 2000-2100 (check constraints).
--   - card_number is stored as text (treat as sensitive; do not log raw values).
-- =============================================================================

create table public.payment_methods (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null,
  card_number text not null,
  holder_name text not null,
  exp_month integer not null,
  exp_year integer not null,
  is_default boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint payment_methods_pkey primary key (id),
  constraint payment_methods_user_id_fkey foreign KEY (user_id) references profiles (id) on delete CASCADE,
  constraint payment_methods_exp_month_valid check (
    (
      (exp_month >= 1)
      and (exp_month <= 12)
    )
  ),
  constraint payment_methods_exp_year_valid check (
    (
      (exp_year >= 2000)
      and (exp_year <= 2100)
    )
  )
) TABLESPACE pg_default;

create index IF not exists payment_methods_user_idx on public.payment_methods using btree (user_id) TABLESPACE pg_default;

create unique INDEX IF not exists payment_methods_one_default_idx on public.payment_methods using btree (user_id) TABLESPACE pg_default
where
  (is_default = true);

create trigger payment_methods_set_updated_at BEFORE
update on payment_methods for EACH row
execute FUNCTION set_updated_at ();
