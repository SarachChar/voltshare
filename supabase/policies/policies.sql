-- =============================================================================
-- RLS policies (public + storage) + Realtime publication
-- -----------------------------------------------------------------------------
-- Final structure (stations own location / photos / businesses / promotions;
-- chargers belong to a station). The live project got here through
-- sql/migrations/001 and 002; a fresh project only needs this file.
--
-- HOW TO RUN
--   Run once in the Supabase SQL Editor AFTER all table files and rls.sql.
--   `create policy` and `alter publication ... add table` are not idempotent:
--   re-running this file errors on objects that already exist.
--
-- OWNERSHIP
--   A host owns a station (stations.host_id = auth.uid()) and, through it,
--   the station's chargers, hours, photos, businesses and promotions.
--
-- SECTIONS
--   1. App tables
--   2. Stations and their child tables
--   3. Storage (bucket voltshare_charger)
--   4. Charging sessions / streams / payments + Realtime
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. App tables
-- -----------------------------------------------------------------------------
create policy "Users can add own booking fees" on public.booking_fee as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM reservations r
  WHERE ((r.id = booking_fee.reservation_id) AND (r.user_id = auth.uid())))));
create policy "Users can view own booking fees" on public.booking_fee as PERMISSIVE for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM reservations r
  WHERE ((r.id = booking_fee.reservation_id) AND (r.user_id = auth.uid())))));
create policy "Users can add own payment methods" on public.payment_methods as PERMISSIVE for INSERT to authenticated with check ((auth.uid() = user_id));
create policy "Users can delete own payment methods" on public.payment_methods as PERMISSIVE for DELETE to authenticated using ((auth.uid() = user_id));
create policy "Users can update own payment methods" on public.payment_methods as PERMISSIVE for UPDATE to authenticated using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));
create policy "Users can view own payment methods" on public.payment_methods as PERMISSIVE for SELECT to authenticated using ((auth.uid() = user_id));
create policy "Profiles are viewable by owner" on public.profiles as PERMISSIVE for SELECT to public using ((auth.uid() = id));
create policy "Users can insert their own profile" on public.profiles as PERMISSIVE for INSERT to public with check ((auth.uid() = id));
create policy "Users can update their own profile" on public.profiles as PERMISSIVE for UPDATE to public using ((auth.uid() = id)) with check ((auth.uid() = id));
create policy "Authenticated can view all reservations" on public.reservations as PERMISSIVE for SELECT to authenticated using (true);
create policy "Users can create own reservations" on public.reservations as PERMISSIVE for INSERT to authenticated with check ((auth.uid() = user_id));
create policy "Users can delete own reservations" on public.reservations as PERMISSIVE for DELETE to authenticated using ((auth.uid() = user_id));
create policy "Users can update own reservations" on public.reservations as PERMISSIVE for UPDATE to public using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));

-- reviews: write-once (no UPDATE / DELETE policies).
create policy "Signed-in users read all reviews"
  on public.reviews for select
  to authenticated
  using (true);

create policy "Drivers review own completed reservations"
  on public.reviews for insert
  to authenticated
  with check (
    exists (
      select 1 from public.reservations r
      where r.id = reviews.reservation_id
        and r.user_id = auth.uid()
        and r.status = 'completed'
    )
  );

-- -----------------------------------------------------------------------------
-- 2. Stations and their child tables
-- -----------------------------------------------------------------------------
-- stations: anyone reads; the host writes their own. No DELETE (no feature).
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

-- chargers: anyone reads; the station's host writes.
create policy "Chargers are viewable by everyone"
  on public.chargers for select to public
  using (true);

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

-- charger_availability: anyone reads; the charger's station host writes.
create policy "Enable read access for all users"
  on public.charger_availability for select to public
  using (true);

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

-- station_* child tables: anyone reads; the station's host writes.
-- Images: insert / update / delete. Businesses & promotions: insert / update
-- only (soft delete via deleted_at).
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
-- 3. Storage (bucket voltshare_charger)
-- -----------------------------------------------------------------------------
-- Paths: station/<station_id>/... and station_business/<station_id>/...
-- Writes: the station's host. Read / delete: any signed-in user (kept as in
-- the original project).
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

create policy "delete charger objects" on storage.objects as PERMISSIVE for DELETE to authenticated using ((bucket_id = 'voltshare_charger'::text));
create policy "read charger objects" on storage.objects as PERMISSIVE for SELECT to authenticated using ((bucket_id = 'voltshare_charger'::text));

-- -----------------------------------------------------------------------------
-- 4. Charging sessions / streams / payments + Realtime
-- -----------------------------------------------------------------------------
-- ACCESS MODEL
--   - Drivers can SELECT only rows belonging to their own reservations.
--   - No INSERT/UPDATE/DELETE policies: all writes go through the ocpp_* SQL
--     functions, executed by edge functions with the service role (which
--     bypasses RLS).
--   - Realtime respects these SELECT policies, so a driver only receives
--     changes for their own sessions.
-- RLS for these three tables is enabled in rls.sql.

create policy "Drivers read own charging sessions"
  on public.charging_sessions for select
  to authenticated
  using (
    exists (
      select 1 from public.reservations r
      where r.id = charging_sessions.reservation_id
        and r.user_id = auth.uid()
    )
  );

create policy "Drivers read own session streams"
  on public.session_streams for select
  to authenticated
  using (
    exists (
      select 1
      from public.charging_sessions s
      join public.reservations r on r.id = s.reservation_id
      where s.id = session_streams.session_id
        and r.user_id = auth.uid()
    )
  );

create policy "Drivers read own session payments"
  on public.session_payments for select
  to authenticated
  using (
    exists (
      select 1
      from public.charging_sessions s
      join public.reservations r on r.id = s.reservation_id
      where s.id = session_payments.session_id
        and r.user_id = auth.uid()
    )
  );

-- Realtime: the app listens for new readings and for the session closing.
alter publication supabase_realtime add table public.charging_sessions;
alter publication supabase_realtime add table public.session_streams;
