-- =============================================================================
-- Table: public.business_images
-- -----------------------------------------------------------------------------
-- Schema reference for the `business_images` table. Kept here for reference
-- while developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Stores the gallery images for a charger's business listing. A charger can
--   have multiple images, ordered by display_order.
--
-- RELATIONSHIPS
--   - charger_id -> chargers(id)  ON DELETE CASCADE
--
-- NOTES
--   - display_order controls the order images appear in the UI (default 0).
-- =============================================================================

create table public.business_images (
  id uuid not null default gen_random_uuid (),
  charger_id uuid not null,
  image_url text not null,
  display_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  constraint business_images_pkey primary key (id),
  constraint fk_business_images_charger foreign KEY (charger_id) references chargers (id) on delete CASCADE
) TABLESPACE pg_default;
