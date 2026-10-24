-- =============================================================================
-- ocpp_start_session
-- -----------------------------------------------------------------------------
--   p_meter_start_wh / p_start_soc / p_power_kw are what the (mock) charger
--   reports when it accepts the start.
--
--   Rules (same as the app's pre-checks, enforced here authoritatively):
--     - reservation exists, belongs to p_user_id, is 'confirmed', no session yet
--     - now >= start_time - 30 min                         (else TOO_EARLY)
--     - now <= start_time + 15 min                         (else RESERVATION_EXPIRED)
--     - if starting early (now < start_time): no other session is charging on
--       the same charger                                   (else CHARGER_IN_USE)
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
--
-- RETURNS jsonb
--   { "ok": true, ...data }  or  { "ok": false, "error_code": "...", "error": "..." }
--   The edge functions map this to the app-facing { success, data } response.
-- =============================================================================

create or replace function public.ocpp_start_session(
  p_reservation_id uuid,
  p_user_id uuid,
  p_meter_start_wh bigint,
  p_start_soc numeric,
  p_power_kw numeric
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_res        reservations%rowtype;
  v_price      numeric(10, 2);
  v_session    charging_sessions%rowtype;
  v_now        timestamptz := now();
begin
  -- Lock the reservation so two concurrent starts serialize.
  select * into v_res from reservations where id = p_reservation_id for update;

  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_NOT_FOUND',
      'error', 'Reservation not found.');
  end if;

  if v_res.user_id <> p_user_id then
    return jsonb_build_object('ok', false, 'error_code', 'NOT_OWNER',
      'error', 'This reservation belongs to another user.');
  end if;

  if exists (select 1 from charging_sessions where reservation_id = v_res.id) then
    return jsonb_build_object('ok', false, 'error_code', 'SESSION_ALREADY_STARTED',
      'error', 'Charging has already been started for this reservation.');
  end if;

  if v_res.status = 'cancelled' then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_CANCELLED',
      'error', 'This reservation has been cancelled.');
  end if;

  if v_res.status <> 'confirmed' then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_NOT_ACTIVE',
      'error', 'This reservation is already ' || v_res.status || '.');
  end if;

  if v_now < v_res.start_time - interval '30 minutes' then
    return jsonb_build_object('ok', false, 'error_code', 'TOO_EARLY',
      'error', 'It is too early to start this reservation.');
  end if;

  if v_now > v_res.start_time + interval '15 minutes' then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_EXPIRED',
      'error', 'Charging must start within 15 minutes of the booked start time.');
  end if;

  if v_now < v_res.start_time and exists (
    select 1
    from charging_sessions s
    join reservations r on r.id = s.reservation_id
    where r.charger_id = v_res.charger_id
      and s.status = 'charging'
  ) then
    return jsonb_build_object('ok', false, 'error_code', 'CHARGER_IN_USE',
      'error', 'The charger is still in use by another driver.');
  end if;

  select coalesce(price_per_kwh, 0) into v_price
  from chargers where id = v_res.charger_id;

  insert into charging_sessions (
    reservation_id, price_per_kwh_at_start, meter_start_wh, started_at, status
  ) values (
    v_res.id, coalesce(v_price, 0), p_meter_start_wh, v_now, 'charging'
  )
  returning * into v_session;

  -- First reading so the app has values immediately (no waiting for a tick).
  insert into session_streams (
    session_id, soc_percent, power_kw, total_energy_received_kwh, created_at
  ) values (
    v_session.id, p_start_soc, p_power_kw, 0, v_now
  );

  -- Keeps the existing "is someone charging" logic and the no-show cron
  -- working off reservations.started_at.
  update reservations set started_at = v_now where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'session_id', v_session.id,
    'transaction_id', v_session.transaction_id,
    'charger_id', v_res.charger_id,
    'meter_start', v_session.meter_start_wh,
    'started_at', v_session.started_at
  );
end;
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.ocpp_start_session(uuid, uuid, bigint, numeric, numeric) from public, anon, authenticated;
grant execute on function public.ocpp_start_session(uuid, uuid, bigint, numeric, numeric) to service_role;
