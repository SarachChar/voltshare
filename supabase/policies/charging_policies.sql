-- =============================================================================
-- RLS + Realtime for charging_sessions / session_streams / session_payments
-- -----------------------------------------------------------------------------
-- HOW TO RUN
--   Run once in the Supabase SQL Editor AFTER the three table files.
--
-- ACCESS MODEL
--   - Drivers can SELECT only rows belonging to their own reservations.
--   - No INSERT/UPDATE/DELETE policies: all writes go through the ocpp_* SQL
--     functions, executed by edge functions with the service role (which
--     bypasses RLS).
--   - Realtime respects these SELECT policies, so a driver only receives
--     changes for their own sessions.
-- =============================================================================

alter table public.charging_sessions enable row level security;
alter table public.session_streams enable row level security;
alter table public.session_payments enable row level security;

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
