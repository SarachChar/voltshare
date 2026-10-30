-- =============================================================================
-- Table: public.profiles
-- -----------------------------------------------------------------------------
-- Schema reference for the `profiles` table. Kept here for reference while
-- developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Stores user profile data (name, phone, email). Referenced by chargers
--   (host_id) and payment_methods (user_id).
--
-- RELATIONSHIPS
--   - No outgoing foreign keys.
--   - Referenced by: chargers.host_id, payment_methods.user_id (both CASCADE).
--
-- TRIGGERS
--   - profiles_set_updated_at: set_updated_at() BEFORE UPDATE. Also fires on
--     the UPDATE branch of an upsert (ProfileService.upsertProfile).
--
-- NOTES
--   - id defaults to gen_random_uuid() and has no FK to auth.users, so linking
--     a profile to its auth user relies on app logic inserting the auth uid.
--   - name, phone, email are all nullable.
-- =============================================================================

create table public.profiles (
  id uuid not null default gen_random_uuid (),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone null default now(),
  name text null,
  phone character varying null,
  email text null,
  constraint profiles_pkey primary key (id)
) TABLESPACE pg_default;

create trigger profiles_set_updated_at before
update on profiles for each row
execute function set_updated_at ();
