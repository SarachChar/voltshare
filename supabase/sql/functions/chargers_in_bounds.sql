-- =============================================================================
-- chargers_in_bounds
-- -----------------------------------------------------------------------------
-- Returns `chargers` rows whose coordinates fall inside the map's currently
-- visible rectangle (the Google Map viewport), with status = 'available',
-- ordered by distance from the user's current location (nearest first).
--
-- Used by the Home/map screen: as the user pans/zooms the map, the app reads
-- the visible region's south-west / north-east corners and calls this function
-- so only the chargers in view are loaded (instead of fetching every charger).
--
-- HOW TO RUN
--   Paste this whole file into the Supabase SQL Editor and run it once. It is
--   idempotent: the extensions use IF NOT EXISTS and the function uses
--   CREATE OR REPLACE, so re-running it is safe.
--
-- DISTANCE
--   Reuses the `earthdistance` + `cube` extensions (great-circle distance in
--   metres), the same approach as `search_chargers`. `chargers.latitude` /
--   `chargers.longitude` are numeric columns, cast to float8 for ll_to_earth().
--
-- BOUNDS
--   min_lat / max_lat are the south / north edges; min_lng / max_lng the west /
--   east edges. The simple `between` test assumes the viewport does NOT cross
--   the antimeridian (±180° longitude), which never happens for Thailand, so no
--   special wrap-around handling is included.
-- =============================================================================

-- 1. Extensions (safe to re-run) ---------------------------------------------
create extension if not exists cube;
create extension if not exists earthdistance;

-- 2. Function -----------------------------------------------------------------
-- Parameters:
--   user_lat, user_lng       the point to sort distances from (map center or
--                            the device location)
--   min_lat, min_lng         south-west corner of the visible region
--   max_lat, max_lng         north-east corner of the visible region
--   page_limit               max rows to return (a safety cap for dense areas)
--
-- Returns every column the app's Charger.fromJson expects, plus distance_m.
create or replace function chargers_in_bounds(
  user_lat     double precision,
  user_lng     double precision,
  min_lat      double precision,
  min_lng      double precision,
  max_lat      double precision,
  max_lng      double precision,
  page_limit   integer           default 200
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
    and c.latitude::float8  between min_lat and max_lat
    and c.longitude::float8 between min_lng and max_lng
  order by distance_m asc, c.created_at desc
  limit greatest(page_limit, 0);
$$;

-- 3. Allow the app's clients to call it ---------------------------------------
grant execute on function chargers_in_bounds(
  double precision, double precision,
  double precision, double precision,
  double precision, double precision,
  integer
) to anon, authenticated;

-- =============================================================================
-- Quick test (optional) — available chargers within a box around central
-- Bangkok, nearest to that same point first:
--   select name, round(distance_m)::int as metres
--   from chargers_in_bounds(13.7460, 100.5340, 13.60, 100.40, 13.90, 100.70, 200);
-- =============================================================================
