-- =============================================================================
-- mock_charger_active_sessions
-- -----------------------------------------------------------------------------
--   Everything the mock charger needs per charging session for one tick: the
--   charger's rated power, when the booking ends, and the latest reading.
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor AFTER the charging tables
--   (charging_sessions, session_streams, session_payments). Uses CREATE OR
--   REPLACE, so re-running is safe.
--
-- WHO CALLS THIS
--   Only the edge functions, using the service role. EXECUTE is revoked from
--   anon/authenticated (bottom of this file), so the app can't call it via RPC
--   and bypass the edge functions' checks.
-- =============================================================================

create or replace function public.mock_charger_active_sessions()
returns table (
  session_id uuid,
  reservation_id uuid,
  transaction_id bigint,
  charger_id uuid,
  meter_start_wh bigint,
  rated_power_kw numeric,
  end_time timestamptz,
  last_soc numeric,
  last_power_kw numeric,
  last_energy_kwh numeric,
  last_reading_at timestamptz
)
language sql
stable
set search_path = public
as $$
  select
    s.id,
    s.reservation_id,
    s.transaction_id,
    r.charger_id,
    s.meter_start_wh,
    coalesce(c.power_kw, 7),
    r.end_time,
    ls.soc_percent,
    ls.power_kw,
    ls.total_energy_received_kwh,
    ls.created_at
  from charging_sessions s
  join reservations r on r.id = s.reservation_id
  join chargers c on c.id = r.charger_id
  left join lateral (
    select st.soc_percent, st.power_kw, st.total_energy_received_kwh, st.created_at
    from session_streams st
    where st.session_id = s.id
    order by st.created_at desc
    limit 1
  ) ls on true
  where s.status = 'charging';
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.mock_charger_active_sessions() from public, anon, authenticated;
grant execute on function public.mock_charger_active_sessions() to service_role;
