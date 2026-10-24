-- =============================================================================
-- charger_review_summary
-- -----------------------------------------------------------------------------
-- Average rating (1 decimal) and number of reviews for one charger, shown next
-- to the charger name ("★ 4.8 (24)") and on the All Reviews screen.
-- average_rating is null when the charger has no reviews.
--
-- SECURITY DEFINER for the same reason as charger_reviews: it has to join
-- reviews -> reservations to find the charger. It only returns aggregates.
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor after reviews.sql. CREATE OR REPLACE, so
--   re-running is safe.
--
-- CALLED BY
--   The app via rpc('charger_review_summary', { p_charger_id }).
-- =============================================================================

create or replace function public.charger_review_summary(p_charger_id uuid)
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
  where r.charger_id = p_charger_id;
$$;

revoke execute on function public.charger_review_summary(uuid) from public, anon;
grant execute on function public.charger_review_summary(uuid) to authenticated;
