-- =============================================================================
-- RLS policies (public + storage) + Realtime publication
-- -----------------------------------------------------------------------------
-- HOW TO RUN
--   Run once in the Supabase SQL Editor AFTER all table files and rls.sql.
--   `create policy` and `alter publication ... add table` are not idempotent:
--   re-running this file errors on objects that already exist.
--
-- SECTIONS
--   1. App tables (exported from the live project's pg_policies)
--   2. Storage (bucket voltshare_charger)
--   3. Charging sessions / streams / payments + Realtime
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
create policy "Enable read access for all users" on public.business_images as PERMISSIVE for SELECT to public using (true);
create policy business_images_insert_owner on public.business_images as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = business_images.charger_id) AND (c.host_id = auth.uid())))));
create policy business_images_update_owner on public.business_images as PERMISSIVE for UPDATE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = business_images.charger_id) AND (c.host_id = auth.uid()))))) with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = business_images.charger_id) AND (c.host_id = auth.uid())))));
create policy "hosts can delete their business images" on public.business_images as PERMISSIVE for DELETE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = business_images.charger_id) AND (c.host_id = auth.uid())))));
create policy "Enable read access for all users" on public.charger_availability as PERMISSIVE for SELECT to public using (true);
create policy charger_availability_insert_owner on public.charger_availability as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_availability.charger_id) AND (c.host_id = auth.uid())))));
create policy charger_availability_update_owner on public.charger_availability as PERMISSIVE for UPDATE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_availability.charger_id) AND (c.host_id = auth.uid()))))) with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_availability.charger_id) AND (c.host_id = auth.uid())))));
create policy "hosts can delete their charger availability" on public.charger_availability as PERMISSIVE for DELETE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_availability.charger_id) AND (c.host_id = auth.uid())))));
create policy "Enable read access for all users" on public.charger_businesses as PERMISSIVE for SELECT to public using (true);
create policy charger_businesses_insert_owner on public.charger_businesses as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_businesses.charger_id) AND (c.host_id = auth.uid())))));
create policy charger_businesses_update_owner on public.charger_businesses as PERMISSIVE for UPDATE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_businesses.charger_id) AND (c.host_id = auth.uid()))))) with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_businesses.charger_id) AND (c.host_id = auth.uid())))));
create policy "Enable read access for all users" on public.charger_images as PERMISSIVE for SELECT to public using (true);
create policy charger_images_insert_owner on public.charger_images as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_images.charger_id) AND (c.host_id = auth.uid())))));
create policy charger_images_update_owner on public.charger_images as PERMISSIVE for UPDATE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_images.charger_id) AND (c.host_id = auth.uid()))))) with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_images.charger_id) AND (c.host_id = auth.uid())))));
create policy "hosts can delete their charger images" on public.charger_images as PERMISSIVE for DELETE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_images.charger_id) AND (c.host_id = auth.uid())))));
create policy "Enable read access for all users" on public.charger_promotions as PERMISSIVE for SELECT to public using (true);
create policy "Hosts can insert their own charger promotions" on public.charger_promotions as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_promotions.charger_id) AND (c.host_id = auth.uid())))));
create policy "Hosts can update their own charger promotions" on public.charger_promotions as PERMISSIVE for UPDATE to authenticated using ((EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = charger_promotions.charger_id) AND (c.host_id = auth.uid())))));
create policy "Chargers are viewable by everyone" on public.chargers as PERMISSIVE for SELECT to public using (true);
create policy "Owners can insert their own chargers" on public.chargers as PERMISSIVE for INSERT to authenticated with check ((auth.uid() = host_id));
create policy "Owners can update their own chargers" on public.chargers as PERMISSIVE for UPDATE to authenticated using ((auth.uid() = host_id)) with check ((auth.uid() = host_id));
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
-- 2. Storage (bucket voltshare_charger)
-- -----------------------------------------------------------------------------
create policy charger_images_storage_insert_owner on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'voltshare_charger'::text) AND (split_part(name, '/'::text, 1) = ANY (ARRAY['charger'::text, 'business'::text])) AND (EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = (split_part(objects.name, '/'::text, 2))::uuid) AND (c.host_id = auth.uid()))))));
create policy charger_images_storage_update_owner on storage.objects as PERMISSIVE for UPDATE to authenticated using (((bucket_id = 'voltshare_charger'::text) AND (split_part(name, '/'::text, 1) = ANY (ARRAY['charger'::text, 'business'::text])) AND (EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = (split_part(objects.name, '/'::text, 2))::uuid) AND (c.host_id = auth.uid())))))) with check (((bucket_id = 'voltshare_charger'::text) AND (split_part(name, '/'::text, 1) = ANY (ARRAY['charger'::text, 'business'::text])) AND (EXISTS ( SELECT 1
   FROM chargers c
  WHERE ((c.id = (split_part(objects.name, '/'::text, 2))::uuid) AND (c.host_id = auth.uid()))))));
create policy "delete charger objects" on storage.objects as PERMISSIVE for DELETE to authenticated using ((bucket_id = 'voltshare_charger'::text));
create policy "read charger objects" on storage.objects as PERMISSIVE for SELECT to authenticated using ((bucket_id = 'voltshare_charger'::text));

-- -----------------------------------------------------------------------------
-- 3. Charging sessions / streams / payments + Realtime
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
