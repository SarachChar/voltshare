-- =============================================================================
-- charger_reviews
-- -----------------------------------------------------------------------------
-- Public list of reviews for one charger, newest first, for the charger
-- details screen ("latest 3") and the All Reviews screen (paged).
--
-- WHY A FUNCTION
--   reviews has no charger_id: the charger and the reviewer come from
--   reservations / profiles, which drivers can't read for other users. This
--   SECURITY DEFINER function joins them on the server and returns only what
--   is safe to show: rating, comment, date and a CENSORED reviewer name.
--   Raw names, user ids and reservation ids never leave the database.
--
-- REVIEWER NAME
--   First character of profiles.name + '***'  (Pong -> P***, ป้อง -> ป***).
--   No name -> 'Anonymous'.
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor after reviews.sql. CREATE OR REPLACE, so
--   re-running is safe.
--
-- CALLED BY
--   The app via rpc('charger_reviews', { p_charger_id, p_limit, p_offset }).
-- =============================================================================

create or replace function public.charger_reviews(
  p_charger_id uuid,
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
  left join profiles p on p.id = r.user_id
  where r.charger_id = p_charger_id
  order by rv.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- Signed-in users only (same audience as the reviews SELECT policy).
revoke execute on function public.charger_reviews(uuid, integer, integer) from public, anon;
grant execute on function public.charger_reviews(uuid, integer, integer) to authenticated;
