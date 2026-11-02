-- =============================================================================
-- Table: public.station_promotions
-- -----------------------------------------------------------------------------
-- PURPOSE
--   Promotional offers shown on a station, with an optional validity window.
--   Replaces charger_promotions (dropped in Task 9).
--
-- RELATIONSHIPS
--   - station_id -> stations(id)  ON DELETE CASCADE
--
-- TRIGGERS
--   - station_promotions_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- NOTES
--   - status: ACTIVE, INACTIVE, EXPIRED (default ACTIVE). The cron job
--     expire-station-promotions flips lapsed ACTIVE rows to EXPIRED.
--   - valid_from / valid_until nullable (NULL = open-ended).
--   - deleted_at = soft delete (NULL = active); there is no DELETE policy.
--   - RLS: enabled below; policies in supabase/policies/policies.sql.
-- =============================================================================

create table public.station_promotions (
  id uuid not null default gen_random_uuid (),
  station_id uuid not null,
  title character varying(255) not null,
  description text null,
  valid_from timestamp with time zone null,
  valid_until timestamp with time zone null,
  status character varying(20) not null default 'ACTIVE'::character varying,
  terms_and_conditions text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone null,
  constraint station_promotions_pkey primary key (id),
  constraint station_promotions_station_id_fkey foreign key (station_id) references stations (id) on delete cascade,
  constraint station_promotions_status_check check (
    (status)::text = any (array['ACTIVE', 'INACTIVE', 'EXPIRED']::text[])
  )
) tablespace pg_default;

create index if not exists station_promotions_station_idx
  on public.station_promotions using btree (station_id) tablespace pg_default;

create trigger station_promotions_set_updated_at before
update on station_promotions for each row
execute function set_updated_at ();

alter table public.station_promotions enable row level security;
