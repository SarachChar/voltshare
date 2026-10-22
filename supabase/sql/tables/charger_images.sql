-- =============================================================================
-- Table: public.charger_images
-- -----------------------------------------------------------------------------
-- Schema reference for the `charger_images` table. Kept here for reference
-- while developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Stores the gallery images for a charger itself. A charger can have multiple
--   images, ordered by display_order.
--
-- RELATIONSHIPS
--   - charger_id -> chargers(id)  ON DELETE CASCADE
--
-- INDEXES
--   - idx_charger_images_charger_id on (charger_id)
--
-- NOTES
--   - display_order is nullable here (contrast with business_images, where it
--     is NOT NULL default 0).
-- =============================================================================

create table public.charger_images (
  id uuid not null default gen_random_uuid (),
  charger_id uuid not null,
  image_url text not null,
  display_order integer null,
  created_at timestamp with time zone not null default now(),
  constraint charger_images_pkey primary key (id),
  constraint charger_images_charger_id_fkey foreign KEY (charger_id) references chargers (id) on delete CASCADE
) TABLESPACE pg_default;

create index IF not exists idx_charger_images_charger_id on public.charger_images using btree (charger_id) TABLESPACE pg_default;
