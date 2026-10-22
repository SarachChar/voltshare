-- =============================================================================
-- Table: public.charger_businesses
-- -----------------------------------------------------------------------------
-- Schema reference for the `charger_businesses` table. Kept here for reference
-- while developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Stores the business profile attached to a charger (e.g. a cafe or
--   restaurant at the charging location), including its type and description.
--
-- RELATIONSHIPS
--   - charger_id -> chargers(id)  ON DELETE CASCADE
--
-- NOTES
--   - business_type is one of: CAFE, RESTAURANT, CO_WORKING, RETAIL,
--     CONVENIENCE, SALON, GYM, OTHER (enforced by a check constraint).
--   - deleted_at supports soft deletes (NULL = active).
-- =============================================================================

create table public.charger_businesses (
  id uuid not null default gen_random_uuid (),
  charger_id uuid not null,
  business_type character varying not null,
  business_name character varying not null,
  description text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone null,
  constraint charger_businesses_pkey primary key (id),
  constraint fk_charger_businesses_charger foreign KEY (charger_id) references chargers (id) on delete CASCADE,
  constraint chk_charger_businesses_business_type check (
    (
      (business_type)::text = any (
        (
          array[
            'CAFE'::character varying,
            'RESTAURANT'::character varying,
            'CO_WORKING'::character varying,
            'RETAIL'::character varying,
            'CONVENIENCE'::character varying,
            'SALON'::character varying,
            'GYM'::character varying,
            'OTHER'::character varying
          ]
        )::text[]
      )
    )
  )
) TABLESPACE pg_default;
