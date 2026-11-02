-- =============================================================================
-- station_review_summary
-- -----------------------------------------------------------------------------
-- Average rating (1 decimal) and number of reviews across every charger of one
-- station, shown next to the station name ("★ 4.8 (24)") and on the All
-- Reviews screen. average_rating is null when the station has no reviews.
--
-- SECURITY DEFINER for the same reason as charger_review_summary: it joins
-- reviews -> reservations -> chargers, which drivers can't read for other
-- users. It only returns aggregates.
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor. CREATE OR REPLACE, so re-running is safe.
--
-- CALLED BY
--   The app via rpc('station_review_summary', { p_station_id }).
-- =============================================================================

create or replace function public.station_review_summary(p_station_id uuid)
returns table (
  average_rating numeric,
  review_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    round(avg(rv.rating)::numeric, 1) as average_rating,
    count(*)::integer as review_count
  from reviews rv
  join reservations r on r.id = rv.reservation_id
  join chargers c on c.id = r.charger_id
  where c.station_id = p_station_id;
$$;

revoke execute on function public.station_review_summary(uuid) from public, anon;
grant execute on function public.station_review_summary(uuid) to authenticated;
