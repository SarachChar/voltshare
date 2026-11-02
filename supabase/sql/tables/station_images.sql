-- =============================================================================
-- Table: public.station_images
-- -----------------------------------------------------------------------------
-- PURPOSE
--   Photo gallery of a station, ordered by display_order. Replaces
--   charger_images (dropped in Task 9).
--
-- RELATIONSHIPS
--   - station_id -> stations(id)  ON DELETE CASCADE
--
-- NOTES
--   - image_url is either a full public URL or a storage path in the
--     `voltshare_charger` bucket: station/<station_id>/<n>.<ext>.
--   - RLS: enabled below; policies in supabase/policies/policies.sql.
-- =============================================================================

create table public.station_images (
  id uuid not null default gen_random_uuid (),
  station_id uuid not null,
  image_url text not null,
  display_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  constraint station_images_pkey primary key (id),
  constraint station_images_station_id_fkey foreign key (station_id) references stations (id) on delete cascade
) tablespace pg_default;

create index if not exists station_images_station_idx
  on public.station_images using btree (station_id) tablespace pg_default;

alter table public.station_images enable row level security;
