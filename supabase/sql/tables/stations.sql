-- =============================================================================
-- Table: public.stations
-- -----------------------------------------------------------------------------
-- PURPOSE
--   A charging location owned by a host (address, pin, description). Each
--   station holds one or more chargers (chargers.station_id). Photos,
--   businesses, business photos and promotions belong to the station
--   (station_images, station_business_images, station_businesses,
--   station_promotions).
--
-- RELATIONSHIPS
--   - host_id -> profiles(id)  ON DELETE CASCADE
--   - Referenced by chargers.station_id and the station_* tables (CASCADE).
--
-- TRIGGERS
--   - stations_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- NOTES
--   - No status column: approval lives on each charger. A station is shown to
--     drivers when it has at least one charger with status 'available'.
--   - latitude/longitude are numeric(10,7), same as chargers, for the
--     earthdistance search functions.
--   - RLS: enabled below; policies in supabase/policies/policies.sql.
--
-- HOW TO RUN
--   Run once in the SQL Editor (needs profiles and set_updated_at()).
-- =============================================================================

create table public.stations (
  id uuid not null default gen_random_uuid (),
  host_id uuid not null,
  name character varying not null,
  description text null,
  address text null,
  latitude numeric(10, 7) null,
  longitude numeric(10, 7) null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint stations_pkey primary key (id),
  constraint stations_host_id_fkey foreign key (host_id) references profiles (id) on delete cascade
) tablespace pg_default;

create index if not exists stations_host_idx
  on public.stations using btree (host_id) tablespace pg_default;

create trigger stations_set_updated_at before
update on stations for each row
execute function set_updated_at ();

alter table public.stations enable row level security;
