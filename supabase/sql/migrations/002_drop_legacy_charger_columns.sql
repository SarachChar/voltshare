-- =============================================================================
-- Migration 002: drop the pre-station charger structure (Task 9)
-- -----------------------------------------------------------------------------
-- After this, a charger's location / owner / photos / businesses / promotions
-- live only on its station.
--
-- RUN ORDER (SQL Editor)
--   1. functions/host_revenue.sql   (the new version: ownership via stations
--                                    only; it no longer reads chargers.host_id)
--   2. this file                     (one transaction: all or nothing)
--   3. Dashboard -> Storage -> voltshare_charger: delete the old charger/ and
--      business/ folders if any are left (SQL can't remove storage files).
--
-- WHAT IT DOES
--   0. Stops if any charger has no station (nothing is changed).
--   1. Unschedules the expire-charger-promotions cron job.
--   2. Replaces the chargers / charger_availability write policies with
--      station-only ownership, and drops the old storage policies for the
--      charger/ and business/ folders. (Policies that reference
--      chargers.host_id must go before the column can be dropped.)
--   3. Drops the charger-level RPCs: search_chargers, chargers_in_bounds,
--      charger_reviews, charger_review_summary.
--   4. Drops charger_images, business_images, charger_businesses,
--      charger_promotions (their policies go with them).
--   5. chargers: station_id NOT NULL; drops host_id, description, address,
--      latitude, longitude.
--
-- On a fresh project you don't run this: the files in tables/, policies/ and
-- functions/ already describe the final structure.
-- =============================================================================

begin;

-- 0. Safety check -------------------------------------------------------------
do $$
declare
  v_orphans integer;
begin
  select count(*) into v_orphans from public.chargers where station_id is null;
  if v_orphans > 0 then
    raise exception
      'Migration 002 stopped: % charger(s) have no station_id. Assign them to a station (or delete them) and run again.',
      v_orphans;
  end if;
end;
$$;

-- 1. Cron that updates a table dropped below --------------------------------
select cron.unschedule(jobid)
from cron.job
where jobname = 'expire-charger-promotions';

-- 2. Policies -------------------------------------------------------------------
drop policy if exists "Owners can insert their own chargers" on public.chargers;
drop policy if exists "Owners can update their own chargers" on public.chargers;

create policy "Owners can insert their own chargers"
  on public.chargers for insert to authenticated
  with check (exists (select 1 from public.stations s
                      where s.id = chargers.station_id and s.host_id = auth.uid()));

create policy "Owners can update their own chargers"
  on public.chargers for update to authenticated
  using      (exists (select 1 from public.stations s
                      where s.id = chargers.station_id and s.host_id = auth.uid()))
  with check (exists (select 1 from public.stations s
                      where s.id = chargers.station_id and s.host_id = auth.uid()));

drop policy if exists charger_availability_insert_owner on public.charger_availability;
drop policy if exists charger_availability_update_owner on public.charger_availability;
drop policy if exists "hosts can delete their charger availability" on public.charger_availability;

create policy charger_availability_insert_owner
  on public.charger_availability for insert to authenticated
  with check (exists (
    select 1 from public.chargers c
    join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id and s.host_id = auth.uid()
  ));

create policy charger_availability_update_owner
  on public.charger_availability for update to authenticated
  using (exists (
    select 1 from public.chargers c
    join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id and s.host_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.chargers c
    join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id and s.host_id = auth.uid()
  ));

create policy "hosts can delete their charger availability"
  on public.charger_availability for delete to authenticated
  using (exists (
    select 1 from public.chargers c
    join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id and s.host_id = auth.uid()
  ));

-- Old storage folders (charger/<charger_id>, business/<charger_id>).
drop policy if exists charger_images_storage_insert_owner on storage.objects;
drop policy if exists charger_images_storage_update_owner on storage.objects;

-- 3. Charger-level RPCs (replaced by the station_* ones) -----------------------
drop function if exists public.search_chargers(
  double precision, double precision, text, text, text,
  double precision, double precision, integer, integer);
drop function if exists public.chargers_in_bounds(
  double precision, double precision, double precision, double precision,
  double precision, double precision, integer);
drop function if exists public.charger_reviews(uuid, integer, integer);
drop function if exists public.charger_review_summary(uuid);

-- 4. Charger-level child tables (replaced by station_*) ------------------------
drop table if exists public.charger_images;
drop table if exists public.business_images;
drop table if exists public.charger_businesses;
drop table if exists public.charger_promotions;

-- 5. chargers: station required; location / owner columns gone ----------------
alter table public.chargers alter column station_id set not null;

alter table public.chargers
  drop column if exists host_id,
  drop column if exists description,
  drop column if exists address,
  drop column if exists latitude,
  drop column if exists longitude;

commit;

-- -----------------------------------------------------------------------------
-- Checks (run after; every row should say ok = true)
-- -----------------------------------------------------------------------------
-- select 'no legacy chargers columns' as check,
--        not exists (select 1 from information_schema.columns
--                    where table_schema = 'public' and table_name = 'chargers'
--                      and column_name in ('host_id','description','address','latitude','longitude')) as ok
-- union all
-- select 'no legacy tables',
--        not exists (select 1 from information_schema.tables
--                    where table_schema = 'public'
--                      and table_name in ('charger_images','business_images','charger_businesses','charger_promotions'))
-- union all
-- select 'no legacy RPCs',
--        not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                    where n.nspname = 'public'
--                      and p.proname in ('search_chargers','chargers_in_bounds','charger_reviews','charger_review_summary'))
-- union all
-- select 'no legacy cron', not exists (select 1 from cron.job where jobname = 'expire-charger-promotions')
-- union all
-- select 'station_id required',
--        (select is_nullable = 'NO' from information_schema.columns
--         where table_schema = 'public' and table_name = 'chargers' and column_name = 'station_id')
-- union all
-- select 'host_revenue has no host_id branch',
--        pg_get_functiondef('public.host_revenue'::regproc) not like '%c.host_id%';
