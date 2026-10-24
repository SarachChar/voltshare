-- =============================================================================
-- ocpp_stop_session
-- -----------------------------------------------------------------------------
--   Closes the charging session for p_reservation_id and creates its bill.
--   p_user_id: the driver stopping it, or NULL when the system auto-stops
--   (time_up / battery_full) – then the ownership check is skipped.
--   p_final_*: the charger's final reading at the stop moment.
--
--   Billing (THB):
--     energy_amount   = round(energy * price_at_start, 2)
--     total_amount    = greatest(energy_amount - booking_fee, 0)
--     platform_amount = round(total_amount * 0.15, 2)
--     host_amount     = total_amount - platform_amount
--   total_amount = 0 -> payment is created already 'paid'.
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

create or replace function public.ocpp_stop_session(
  p_reservation_id uuid,
  p_user_id uuid,
  p_stop_reason text,
  p_final_soc numeric,
  p_final_power_kw numeric,
  p_final_energy_kwh numeric
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_res          reservations%rowtype;
  v_session      charging_sessions%rowtype;
  v_now          timestamptz := now();
  v_energy       numeric(10, 3);
  v_fee          numeric(10, 2);
  v_energy_amt   numeric(10, 2);
  v_total        numeric(10, 2);
  v_platform     numeric(10, 2);
  v_payment_id   uuid;
  v_pay_status   text;
begin
  select * into v_res from reservations where id = p_reservation_id;
  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_NOT_FOUND',
      'error', 'Reservation not found.');
  end if;

  if p_user_id is not null and v_res.user_id <> p_user_id then
    return jsonb_build_object('ok', false, 'error_code', 'NOT_OWNER',
      'error', 'This reservation belongs to another user.');
  end if;

  select * into v_session
  from charging_sessions
  where reservation_id = v_res.id
  for update;

  if not found or v_session.status <> 'charging' then
    return jsonb_build_object('ok', false, 'error_code', 'NO_ACTIVE_TRANSACTION',
      'error', 'There is no charging session in progress for this reservation.');
  end if;

  v_energy := round(greatest(p_final_energy_kwh, 0), 3);

  -- Final reading at the exact stop moment.
  insert into session_streams (
    session_id, soc_percent, power_kw, total_energy_received_kwh, created_at
  ) values (
    v_session.id, least(greatest(p_final_soc, 0), 100), 0, v_energy, v_now
  );

  update charging_sessions
  set status = 'completed',
      ended_at = v_now,
      stop_reason = p_stop_reason,
      total_energy_kwh = v_energy,
      meter_stop_wh = v_session.meter_start_wh + round(v_energy * 1000)::bigint
  where id = v_session.id
  returning * into v_session;

  update reservations set status = 'completed' where id = v_res.id;

  -- Bill.
  select coalesce(sum(amount), 0) into v_fee
  from booking_fee where reservation_id = v_res.id;

  v_energy_amt := round(v_energy * v_session.price_per_kwh_at_start, 2);
  v_total      := greatest(v_energy_amt - v_fee, 0);
  v_platform   := round(v_total * 0.15, 2);
  v_pay_status := case when v_total = 0 then 'paid' else 'unpaid' end;

  insert into session_payments (
    session_id, energy_amount, booking_fee_deducted, total_amount,
    platform_amount, host_amount, status, paid_at
  ) values (
    v_session.id, v_energy_amt, v_fee, v_total,
    v_platform, v_total - v_platform, v_pay_status,
    case when v_pay_status = 'paid' then v_now end
  )
  returning id into v_payment_id;

  return jsonb_build_object(
    'ok', true,
    'session_id', v_session.id,
    'transaction_id', v_session.transaction_id,
    'charger_id', v_res.charger_id,
    'meter_stop', v_session.meter_stop_wh,
    'stopped_at', v_session.ended_at,
    'stop_reason', v_session.stop_reason,
    'total_energy_kwh', v_session.total_energy_kwh,
    'payment_id', v_payment_id,
    'payment_status', v_pay_status,
    'total_amount', v_total
  );
end;
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.ocpp_stop_session(uuid, uuid, text, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.ocpp_stop_session(uuid, uuid, text, numeric, numeric, numeric) to service_role;
