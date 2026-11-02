-- =============================================================================
-- Migration 001: station layer (Task 1)
-- -----------------------------------------------------------------------------
-- Adds ownership rules for stations and the station_* tables, and lets the
-- chargers / charger_availability policies check ownership through the
-- station as well as the old chargers.host_id.
--
-- RUN ORDER (SQL Editor, once)
--   1. tables/stations.sql
--   2. tables/station_images.sql, station_business_images.sql,
--      station_businesses.sql, station_promotions.sql
--   3. the "Station layer" ALTER block at the bottom of tables/chargers.sql
--   4. this file
--   5. cron/expire_station_promotions.sql
--   6. seed/reset_charger_data.sql, then seed/mock_stations.sql
--
-- On a fresh project this runs after policies/rls.sql + policies/policies.sql.
--
-- OWNERSHIP RULE FOR A CHARGER (used by every policy below)
--   The charger's station belongs to auth.uid(), or (legacy rows with no
--   station yet) chargers.host_id = auth.uid(). The legacy branch requires
--   station_id IS NULL, so a host can't attach a charger to someone else's
--   station by setting host_id to themselves. Task 9 removes the legacy branch.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. stations: anyone reads; the host writes their own. No DELETE (no feature).
-- -----------------------------------------------------------------------------
create policy "Stations are viewable by everyone"
  on public.stations for select to public
  using (true);

create policy "Hosts can insert their own stations"
  on public.stations for insert to authenticated
  with check (auth.uid() = host_id);

create policy "Hosts can update their own stations"
  on public.stations for update to authenticated
  using (auth.uid() = host_id)
  with check (auth.uid() = host_id);

-- -----------------------------------------------------------------------------
-- 2. station_* child tables: anyone reads; the station's host writes.
--    Images: insert/update/delete. Businesses & promotions: insert/update only
--    (soft delete via deleted_at).
-- -----------------------------------------------------------------------------
create policy "Station images are viewable by everyone"
  on public.station_images for select to public using (true);
create policy "Hosts can insert their station images"
  on public.station_images for insert to authenticated
  with check (exists (select 1 from public.stations s
                      where s.id = station_images.station_id and s.host_id = auth.uid()));
create policy "Hosts can update their station images"
  on public.station_images for update to authenticated
  using      (exists (select 1 from public.stations s
                      where s.id = station_images.station_id and s.host_id = auth.uid()))
  with check (exists (select 1 from public.stations s
                      where s.id = station_images.station_id and s.host_id = auth.uid()));
create policy "Hosts can delete their station images"
  on public.station_images for delete to authenticated
  using (exists (select 1 from public.stations s
                 where s.id = station_images.station_id and s.host_id = auth.uid()));

create policy "Station business images are viewable by everyone"
  on public.station_business_images for select to public using (true);
create policy "Hosts can insert their station business images"
  on public.station_business_images for insert to authenticated
  with check (exists (select 1 from public.stations s
                      where s.id = station_business_images.station_id and s.host_id = auth.uid()));
create policy "Hosts can update their station business images"
  on public.station_business_images for update to authenticated
  using      (exists (select 1 from public.stations s
                      where s.id = station_business_images.station_id and s.host_id = auth.uid()))
  with check (exists (select 1 from public.stations s
                      where s.id = station_business_images.station_id and s.host_id = auth.uid()));
create policy "Hosts can delete their station business images"
  on public.station_business_images for delete to authenticated
  using (exists (select 1 from public.stations s
                 where s.id = station_business_images.station_id and s.host_id = auth.uid()));

create policy "Station businesses are viewable by everyone"
  on public.station_businesses for select to public using (true);
create policy "Hosts can insert their station businesses"
  on public.station_businesses for insert to authenticated
  with check (exists (select 1 from public.stations s
                      where s.id = station_businesses.station_id and s.host_id = auth.uid()));
create policy "Hosts can update their station businesses"
  on public.station_businesses for update to authenticated
  using      (exists (select 1 from public.stations s
                      where s.id = station_businesses.station_id and s.host_id = auth.uid()))
  with check (exists (select 1 from public.stations s
                      where s.id = station_businesses.station_id and s.host_id = auth.uid()));

create policy "Station promotions are viewable by everyone"
  on public.station_promotions for select to public using (true);
create policy "Hosts can insert their station promotions"
  on public.station_promotions for insert to authenticated
  with check (exists (select 1 from public.stations s
                      where s.id = station_promotions.station_id and s.host_id = auth.uid()));
create policy "Hosts can update their station promotions"
  on public.station_promotions for update to authenticated
  using      (exists (select 1 from public.stations s
                      where s.id = station_promotions.station_id and s.host_id = auth.uid()))
  with check (exists (select 1 from public.stations s
                      where s.id = station_promotions.station_id and s.host_id = auth.uid()));

-- -----------------------------------------------------------------------------
-- 3. chargers: replace the host_id-only write policies.
-- -----------------------------------------------------------------------------
drop policy "Owners can insert their own chargers" on public.chargers;
drop policy "Owners can update their own chargers" on public.chargers;

create policy "Owners can insert their own chargers"
  on public.chargers for insert to authenticated
  with check (
    exists (select 1 from public.stations s
            where s.id = chargers.station_id and s.host_id = auth.uid())
    or (chargers.station_id is null and auth.uid() = chargers.host_id)
  );

create policy "Owners can update their own chargers"
  on public.chargers for update to authenticated
  using (
    exists (select 1 from public.stations s
            where s.id = chargers.station_id and s.host_id = auth.uid())
    or (chargers.station_id is null and auth.uid() = chargers.host_id)
  )
  with check (
    exists (select 1 from public.stations s
            where s.id = chargers.station_id and s.host_id = auth.uid())
    or (chargers.station_id is null and auth.uid() = chargers.host_id)
  );

-- -----------------------------------------------------------------------------
-- 4. charger_availability: same ownership rule, through the charger.
-- -----------------------------------------------------------------------------
drop policy charger_availability_insert_owner on public.charger_availability;
drop policy charger_availability_update_owner on public.charger_availability;
drop policy "hosts can delete their charger availability" on public.charger_availability;

create policy charger_availability_insert_owner
  on public.charger_availability for insert to authenticated
  with check (exists (
    select 1 from public.chargers c
    left join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id
      and (s.host_id = auth.uid() or (c.station_id is null and c.host_id = auth.uid()))
  ));

create policy charger_availability_update_owner
  on public.charger_availability for update to authenticated
  using (exists (
    select 1 from public.chargers c
    left join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id
      and (s.host_id = auth.uid() or (c.station_id is null and c.host_id = auth.uid()))
  ))
  with check (exists (
    select 1 from public.chargers c
    left join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id
      and (s.host_id = auth.uid() or (c.station_id is null and c.host_id = auth.uid()))
  ));

create policy "hosts can delete their charger availability"
  on public.charger_availability for delete to authenticated
  using (exists (
    select 1 from public.chargers c
    left join public.stations s on s.id = c.station_id
    where c.id = charger_availability.charger_id
      and (s.host_id = auth.uid() or (c.station_id is null and c.host_id = auth.uid()))
  ));

-- -----------------------------------------------------------------------------
-- 5. Storage (bucket voltshare_charger): station photo folders.
--    Paths: station/<station_id>/... and station_business/<station_id>/...
--    The existing charger/ and business/ policies stay until Task 9.
--    SELECT and DELETE are already covered by "read charger objects" /
--    "delete charger objects" (any path in the bucket).
-- -----------------------------------------------------------------------------
create policy station_images_storage_insert_owner
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'voltshare_charger'
    and split_part(name, '/', 1) = any (array['station', 'station_business'])
    and exists (select 1 from public.stations s
                where s.id::text = split_part(objects.name, '/', 2)
                  and s.host_id = auth.uid())
  );

create policy station_images_storage_update_owner
  on storage.objects for update to authenticated
  using (
    bucket_id = 'voltshare_charger'
    and split_part(name, '/', 1) = any (array['station', 'station_business'])
    and exists (select 1 from public.stations s
                where s.id::text = split_part(objects.name, '/', 2)
                  and s.host_id = auth.uid())
  )
  with check (
    bucket_id = 'voltshare_charger'
    and split_part(name, '/', 1) = any (array['station', 'station_business'])
    and exists (select 1 from public.stations s
                where s.id::text = split_part(objects.name, '/', 2)
                  and s.host_id = auth.uid())
  );

commit;
