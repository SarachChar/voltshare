-- =============================================================================
-- stations_in_bounds
-- -----------------------------------------------------------------------------
-- Returns the stations whose pin falls inside the map's visible rectangle and
-- that have at least one charger with status = 'available', ordered by
-- distance from the user (nearest first). Each row carries a summary of the
-- station's live chargers so the map popup needs no extra query.
--
-- Used by the Home/map screen (replaces chargers_in_bounds there).
--
-- HOW TO RUN
--   Paste into the Supabase SQL Editor and run once. Idempotent
--   (CREATE OR REPLACE).
--
-- SUMMARY COLUMNS (computed over the station's 'available' chargers only)
--   available_count   number of available chargers (>= 1)
--   charger_count     all live chargers ('available' + 'unavailable'), so the
--                     popup can show "2/3 available"
--   connector_types   distinct connector types, sorted, e.g. {CCS2,"Type 2"}
--   charger_types     distinct current types, sorted, e.g. {AC,DC}
--   min_price         cheapest price_per_kwh
--   max_power_kw      highest power_kw
--
-- DISTANCE / SEARCH PATH
--   earthdistance + cube (see search_chargers.sql). No `set search_path`, so
--   ll_to_earth resolves through the API's search path (public, extensions).
--   If you add one, use `set search_path = public, extensions`.
--
-- BOUNDS
--   min/max lat = south/north edges, min/max lng = west/east edges. No
--   antimeridian handling (not needed for Thailand).
-- =============================================================================

create or replace function stations_in_bounds(
  user_lat     double precision,
  user_lng     double precision,
  min_lat      double precision,
  min_lng      double precision,
  max_lat      double precision,
  max_lng      double precision,
  page_limit   integer           default 200
)
returns table (
  id               uuid,
  host_id          uuid,
  name             text,
  description      text,
  address          text,
  latitude         numeric,
  longitude        numeric,
  created_at       timestamptz,
  distance_m       double precision,
  charger_count    integer,
  available_count  integer,
  connector_types  text[],
  charger_types    text[],
  min_price        numeric,
  max_power_kw     numeric
)
language sql
stable
as $$
  select
    s.id,
    s.host_id,
    s.name,
    s.description,
    s.address,
    s.latitude,
    s.longitude,
    s.created_at,
    earth_distance(
      ll_to_earth(user_lat, user_lng),
      ll_to_earth(s.latitude::float8, s.longitude::float8)
    ) as distance_m,
    agg.charger_count,
    agg.available_count,
    agg.connector_types,
    agg.charger_types,
    agg.min_price,
    agg.max_power_kw
  from stations s
  cross join lateral (
    select
      count(*)::integer as charger_count,
      count(*) filter (where c.status = 'available')::integer as available_count,
      coalesce(array_agg(distinct c.connector_type::text order by c.connector_type::text)
        filter (where c.status = 'available' and c.connector_type is not null), '{}') as connector_types,
      coalesce(array_agg(distinct c.charger_type::text order by c.charger_type::text)
        filter (where c.status = 'available' and c.charger_type is not null), '{}') as charger_types,
      min(c.price_per_kwh) filter (where c.status = 'available') as min_price,
      max(c.power_kw)      filter (where c.status = 'available') as max_power_kw
    from chargers c
    where c.station_id = s.id
      and c.status in ('available', 'unavailable')
  ) agg
  where agg.available_count > 0
    and s.latitude::float8  between min_lat and max_lat
    and s.longitude::float8 between min_lng and max_lng
  order by distance_m asc, s.created_at desc
  limit greatest(page_limit, 0);
$$;

grant execute on function stations_in_bounds(
  double precision, double precision,
  double precision, double precision,
  double precision, double precision,
  integer
) to anon, authenticated;

-- =============================================================================
-- Quick test — stations around central Bangkok, nearest first:
--   select name, available_count, charger_count, connector_types, min_price,
--          round(distance_m)::int as metres
--   from stations_in_bounds(13.7460, 100.5340, 13.60, 100.40, 13.90, 100.70, 200);
-- =============================================================================
