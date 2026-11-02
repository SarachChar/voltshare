-- =============================================================================
-- search_stations
-- -----------------------------------------------------------------------------
-- Distance-sorted, paginated station search for the app's Search screen
-- (replaces search_chargers there).
--
-- HOW TO RUN
--   Paste into the Supabase SQL Editor and run once. Idempotent
--   (CREATE OR REPLACE).
--
-- WHAT IT RETURNS
--   Stations with at least one 'available' charger that matches ALL the
--   charger filters (type / connector / power) on the SAME charger, nearest to
--   the user first, LIMIT/OFFSET paged. Same columns as stations_in_bounds, so
--   the app parses both with Station.fromJson.
--
--   The summary columns (available_count, connector_types, min_price, ...) are
--   computed over all of the station's available chargers, not only the ones
--   matching the filters, so a card looks the same as on the map.
--
-- PARAMETERS (pass NULL to skip a filter)
--   search_query            case-insensitive substring match on stations.name
--   charger_type_filter     'AC' | 'DC'
--   connector_type_filter   'CCS2' | 'Type 2' | 'CHAdeMO'
--   power_min / power_max   power_kw half-open range [min, max)
--   page_limit, page_offset pagination (app sends 20 / multiples of 20)
--
-- DISTANCE / SEARCH PATH
--   earthdistance + cube; no `set search_path` (see stations_in_bounds.sql).
-- =============================================================================

create or replace function search_stations(
  user_lat               double precision,
  user_lng               double precision,
  search_query           text               default null,
  charger_type_filter    text               default null,
  connector_type_filter  text               default null,
  power_min              double precision   default null,
  power_max              double precision   default null,
  page_limit             integer            default 20,
  page_offset            integer            default 0
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
    -- Name search (skipped when null/blank).
    and (
      search_query is null
      or btrim(search_query) = ''
      or s.name ilike '%' || btrim(search_query) || '%'
    )
    -- Every charger filter must hold on the same available charger.
    and exists (
      select 1
      from chargers c
      where c.station_id = s.id
        and c.status = 'available'
        and (charger_type_filter   is null or c.charger_type   = charger_type_filter)
        and (connector_type_filter is null or c.connector_type = connector_type_filter)
        and (power_min is null or c.power_kw >= power_min)
        and (power_max is null or c.power_kw <  power_max)
    )
  order by distance_m asc, s.created_at desc
  limit  greatest(page_limit, 0)
  offset greatest(page_offset, 0);
$$;

grant execute on function search_stations(
  double precision, double precision, text, text, text,
  double precision, double precision, integer, integer
) to anon, authenticated;

-- =============================================================================
-- Quick tests
--
-- 1) Nearest stations to central Bangkok:
--   select name, available_count, connector_types, round(distance_m)::int as m
--   from search_stations(13.7460, 100.5340, null, null, null, null, null, 20, 0);
--
-- 2) DC + CCS2 + >= 50 kW:
--   select name, connector_types, max_power_kw
--   from search_stations(13.7460, 100.5340, null, 'DC', 'CCS2', 50, null, 20, 0);
--
-- 3) Same-charger rule. Stations that have an available AC charger and an
--    available CHAdeMO charger, but no single available AC + CHAdeMO charger
--    (CHAdeMO is always DC in the seed). They must NOT come back for AC +
--    CHAdeMO. "candidates" should be > 0 on the mock seed; "leaked" must be 0:
--   with candidates as (
--     select s.id from stations s
--     where exists (select 1 from chargers c where c.station_id = s.id
--                   and c.status = 'available' and c.charger_type = 'AC')
--       and exists (select 1 from chargers c where c.station_id = s.id
--                   and c.status = 'available' and c.connector_type = 'CHAdeMO')
--       and not exists (select 1 from chargers c where c.station_id = s.id
--                   and c.status = 'available' and c.charger_type = 'AC'
--                   and c.connector_type = 'CHAdeMO')
--   )
--   select
--     (select count(*) from candidates) as candidates,
--     (select count(*) from search_stations(13.7460, 100.5340, null, 'AC', 'CHAdeMO',
--                                           null, null, 1000, 0) r
--      where r.id in (select id from candidates)) as leaked;
-- =============================================================================
