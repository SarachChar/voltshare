-- =============================================================================
-- station_reviews
-- -----------------------------------------------------------------------------
-- Public list of reviews across every charger of one station, newest first,
-- for the station details screen ("latest 3") and the All Reviews screen
-- (paged).
--
-- WHY A FUNCTION
--   Same as charger_reviews: reviews has no station_id and drivers can't read
--   other users' reservations / profiles. This SECURITY DEFINER function joins
--   them on the server and returns only rating, comment, date and a CENSORED
--   reviewer name (first character + '***', or 'Anonymous').
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor. CREATE OR REPLACE, so re-running is safe.
--
-- CALLED BY
--   The app via rpc('station_reviews', { p_station_id, p_limit, p_offset }).
-- =============================================================================

create or replace function public.station_reviews(
  p_station_id uuid,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  rating integer,
  comment text,
  created_at timestamptz,
  reviewer_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    rv.id,
    rv.rating,
    rv.comment,
    rv.created_at,
    case
      when coalesce(btrim(p.name), '') = '' then 'Anonymous'
      else left(btrim(p.name), 1) || '***'
    end as reviewer_name
  from reviews rv
  join reservations r on r.id = rv.reservation_id
  join chargers c on c.id = r.charger_id
  left join profiles p on p.id = r.user_id
  where c.station_id = p_station_id
  order by rv.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke execute on function public.station_reviews(uuid, integer, integer) from public, anon;
grant execute on function public.station_reviews(uuid, integer, integer) to authenticated;
