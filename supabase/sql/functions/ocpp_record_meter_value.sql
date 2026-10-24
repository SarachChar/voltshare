-- =============================================================================
-- ocpp_record_meter_value
-- -----------------------------------------------------------------------------
--   Stores one MeterValues sample. p_register_wh is the charger's cumulative
--   energy register (OCPP Energy.Active.Import.Register, Wh); the energy for
--   this session is register - meter_start_wh. Rejected if the transaction
--   isn't charging any more (e.g. a tick that raced with a stop).
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

create or replace function public.ocpp_record_meter_value(
  p_transaction_id bigint,
  p_soc numeric,
  p_power_kw numeric,
  p_register_wh numeric,
  p_timestamp timestamptz default now()
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_session charging_sessions%rowtype;
begin
  -- Share lock: blocks a concurrent stop from closing the session mid-insert.
  select * into v_session
  from charging_sessions
  where transaction_id = p_transaction_id
  for share;

  if not found or v_session.status <> 'charging' then
    return jsonb_build_object('ok', false, 'error_code', 'NO_ACTIVE_TRANSACTION',
      'error', 'No active transaction with this id.');
  end if;

  insert into session_streams (
    session_id, soc_percent, power_kw, total_energy_received_kwh, created_at
  ) values (
    v_session.id,
    least(greatest(p_soc, 0), 100),
    greatest(p_power_kw, 0),
    round(greatest(p_register_wh - v_session.meter_start_wh, 0) / 1000.0, 3),
    coalesce(p_timestamp, now())
  );

  return jsonb_build_object('ok', true, 'session_id', v_session.id);
end;
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.ocpp_record_meter_value(bigint, numeric, numeric, numeric, timestamptz) from public, anon, authenticated;
grant execute on function public.ocpp_record_meter_value(bigint, numeric, numeric, numeric, timestamptz) to service_role;
