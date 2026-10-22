-- =============================================================================
-- Table: public.charger_availability
-- -----------------------------------------------------------------------------
-- Schema reference for the `charger_availability` table. Kept here for
-- reference while developing features; this mirrors the live table definition
-- in Supabase.
--
-- PURPOSE
--   Defines the weekly availability windows for a charger. Each row is a time
--   slot on a given day of the week during which the charger is bookable.
--
-- RELATIONSHIPS
--   - charger_id -> chargers(id)  ON DELETE CASCADE
--
-- INDEXES
--   - idx_charger_availability_charger_id on (charger_id)
--
-- NOTES
--   - day_of_week is 0-6 (0 = Sunday ... 6 = Saturday), enforced by a check.
--   - start_time must be strictly before end_time (check constraint).
--   - is_available lets a slot be toggled off without deleting the row.
-- =============================================================================

create table public.charger_availability (
  id uuid not null default gen_random_uuid (),
  charger_id uuid not null,
  day_of_week integer not null,
  start_time time without time zone not null,
  end_time time without time zone not null,
  is_available boolean not null default true,
  created_at timestamp with time zone not null default now(),
  constraint charger_availability_pkey primary key (id),
  constraint charger_availability_charger_id_fkey foreign KEY (charger_id) references chargers (id) on delete CASCADE,
  constraint charger_availability_day_of_week_check check (
    (
      (day_of_week >= 0)
      and (day_of_week <= 6)
    )
  ),
  constraint charger_availability_time_check check ((start_time < end_time))
) TABLESPACE pg_default;

create index IF not exists idx_charger_availability_charger_id on public.charger_availability using btree (charger_id) TABLESPACE pg_default;
