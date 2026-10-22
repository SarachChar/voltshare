-- =============================================================================
-- Table: public.charger_promotions
-- -----------------------------------------------------------------------------
-- Schema reference for the `charger_promotions` table. Kept here for reference
-- while developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Stores promotional offers attached to a charger, with an optional validity
--   window and terms. Used to surface deals on the charger listing.
--
-- RELATIONSHIPS
--   - charger_id -> chargers(id)  ON DELETE CASCADE
--
-- NOTES
--   - status is one of: ACTIVE, INACTIVE, EXPIRED (default ACTIVE), enforced by
--     a check constraint.
--   - valid_from / valid_until are nullable (NULL = open-ended).
--   - deleted_at supports soft deletes (NULL = active).
-- =============================================================================

create table public.charger_promotions (
  id uuid not null default gen_random_uuid (),
  charger_id uuid not null,
  title character varying(255) not null,
  description text null,
  valid_from timestamp with time zone null,
  valid_until timestamp with time zone null,
  status character varying(20) not null default 'ACTIVE'::character varying,
  terms_and_conditions text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone null,
  constraint charger_promotions_pkey primary key (id),
  constraint charger_promotions_charger_id_fkey foreign KEY (charger_id) references chargers (id) on delete CASCADE,
  constraint charger_promotions_status_check check (
    (
      (status)::text = any (
        (
          array[
            'ACTIVE'::character varying,
            'INACTIVE'::character varying,
            'EXPIRED'::character varying
          ]
        )::text[]
      )
    )
  )
) TABLESPACE pg_default;
