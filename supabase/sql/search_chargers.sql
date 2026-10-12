-- =============================================================================
-- search_chargers
-- -----------------------------------------------------------------------------
-- Distance-sorted, paginated search over the `chargers` table, used by the
-- app's Search screen.
--
-- HOW TO RUN
--   Paste this whole file into the Supabase SQL Editor and run it once. It is
--   idempotent: the extensions use IF NOT EXISTS and the function uses
--   CREATE OR REPLACE, so re-running it is safe (e.g. after editing the logic).
--
-- WHAT IT DOES
--   Given the user's current location, returns `chargers` rows with
--   status = 'available', ordered by distance (nearest first), with optional
--   name search and charger-type / connector-type / power filters, and
--   LIMIT/OFFSET paging (20 at a time from the app).
--
-- DISTANCE
--   Uses the `earthdistance` + `cube` extensions (great-circle distance in
--   metres). `chargers.latitude` / `chargers.longitude` are numeric columns, so
--   they are cast to float8 for ll_to_earth(). No schema change is required and
--   no geometry column is added.
-- =============================================================================

-- 1. Extensions (safe to re-run) ---------------------------------------------
create extension if not exists cube;
create extension if not exists earthdistance;

-- 2. Function -----------------------------------------------------------------
-- Parameters (all filters are optional; pass NULL to skip a filter):
--   user_lat, user_lng       the point to sort distances from
--   search_query             case-insensitive substring match on name
--   charger_type_filter      'AC' | 'DC'
--   connector_type_filter    'CCS2' | 'Type 2' | 'CHAdeMO'
--   power_min / power_max     power_kw range in kW, half-open [min, max):
--                               '< 11'   -> power_min = NULL, power_max = 11
--                               '11-50'  -> power_min = 11,   power_max = 50
--                               '> 50'   -> power_min = 50,   power_max = NULL
--   page_limit, page_offset   pagination (app sends 20 / multiples of 20)
--
-- Returns every column the app's Charger.fromJson expects, plus distance_m.
create or replace function search_chargers(
  user_lat               double precision,
  user_lng               double precision,
  search_query           text               default null,
  charger_type_filter    text               default null,
  connector_type_filter  text               default null,
  power_min              double precision    default null,
  power_max              double precision    default null,
  page_limit             integer             default 20,
  page_offset            integer             default 0
)
returns table (
  id             uuid,
  host_id        uuid,
  name           text,
  description    text,
  address        text,
  latitude       numeric,
  longitude      numeric,
  charger_type   text,
  connector_type text,
  power_kw       numeric,
  price_per_kwh  numeric,
  status         text,
  created_at     timestamptz,
  distance_m     double precision
)
language sql
stable
as $$
  select
    c.id,
    c.host_id,
    c.name,
    c.description,
    c.address,
    c.latitude,
    c.longitude,
    c.charger_type,
    c.connector_type,
    c.power_kw,
    c.price_per_kwh,
    c.status,
    c.created_at,
    earth_distance(
      ll_to_earth(user_lat, user_lng),
      ll_to_earth(c.latitude::float8, c.longitude::float8)
    ) as distance_m
  from chargers c
  where c.status = 'available'
    -- Name search (skipped when search_query is null/blank).
    and (
      search_query is null
      or btrim(search_query) = ''
      or c.name ilike '%' || btrim(search_query) || '%'
    )
    -- Charger type: 'AC' / 'DC' (skipped when null).
    and (charger_type_filter is null or c.charger_type = charger_type_filter)
    -- Connector type: 'CCS2' / 'Type 2' / 'CHAdeMO' (skipped when null).
    and (connector_type_filter is null or c.connector_type = connector_type_filter)
    -- Power range, half-open [power_min, power_max). Either bound may be null.
    and (power_min is null or c.power_kw >= power_min)
    and (power_max is null or c.power_kw <  power_max)
  order by distance_m asc, c.created_at desc
  limit  greatest(page_limit, 0)
  offset greatest(page_offset, 0);
$$;

-- 3. Allow the app's clients to call it ---------------------------------------
-- Supabase exposes SECURITY INVOKER functions over PostgREST; grant execute to
-- the roles your app uses. (Row-Level Security on `chargers` still applies.)
grant execute on function search_chargers(
  double precision, double precision, text, text, text,
  double precision, double precision, integer, integer
) to anon, authenticated;

-- =============================================================================
-- Quick test (optional) — nearest available chargers to central Bangkok:
--   select name, charger_type, connector_type, power_kw,
--          round(distance_m)::int as metres
--   from search_chargers(13.7460, 100.5340, null, null, null, null, null, 20, 0);
--
-- With filters — DC + CCS2 + power >= 50 kW:
--   select name, power_kw, round(distance_m)::int as metres
--   from search_chargers(13.7460, 100.5340, null, 'DC', 'CCS2', 50, null, 20, 0);
-- =============================================================================
