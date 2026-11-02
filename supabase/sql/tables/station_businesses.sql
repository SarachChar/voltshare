-- =============================================================================
-- Table: public.station_businesses
-- -----------------------------------------------------------------------------
-- PURPOSE
--   Businesses drivers can use while charging at a station (cafe, gym, ...).
--   Replaces charger_businesses (dropped in Task 9).
--
-- RELATIONSHIPS
--   - station_id -> stations(id)  ON DELETE CASCADE
--
-- TRIGGERS
--   - station_businesses_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- NOTES
--   - business_type: CAFE, RESTAURANT, CO_WORKING, RETAIL, CONVENIENCE,
--     SALON, GYM, OTHER (same values as charger_businesses).
--   - deleted_at = soft delete (NULL = active); there is no DELETE policy.
--   - RLS: enabled below; policies in supabase/policies/policies.sql.
-- =============================================================================

create table public.station_businesses (
  id uuid not null default gen_random_uuid (),
  station_id uuid not null,
  business_type character varying not null,
  business_name character varying not null,
  description text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone null,
  constraint station_businesses_pkey primary key (id),
  constraint station_businesses_station_id_fkey foreign key (station_id) references stations (id) on delete cascade,
  constraint station_businesses_business_type_check check (
    (business_type)::text = any (
      array['CAFE', 'RESTAURANT', 'CO_WORKING', 'RETAIL',
            'CONVENIENCE', 'SALON', 'GYM', 'OTHER']::text[]
    )
  )
) tablespace pg_default;

create index if not exists station_businesses_station_idx
  on public.station_businesses using btree (station_id) tablespace pg_default;

create trigger station_businesses_set_updated_at before
update on station_businesses for each row
execute function set_updated_at ();

alter table public.station_businesses enable row level security;
