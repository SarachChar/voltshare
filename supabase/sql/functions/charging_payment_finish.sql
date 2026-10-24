-- =============================================================================
-- charging_payment_finish
-- -----------------------------------------------------------------------------
--   Records the outcome of the card charge. Never downgrades a 'paid' row.
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

create or replace function public.charging_payment_finish(
  p_payment_id uuid,
  p_payment_method_id uuid,
  p_success boolean,
  p_transaction_id text
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_payment session_payments%rowtype;
begin
  update session_payments
  set status = case when p_success then 'paid' else 'failed' end,
      payment_method_id = p_payment_method_id,
      transaction_id = case when p_success then p_transaction_id else transaction_id end,
      paid_at = case when p_success then now() else paid_at end
  where id = p_payment_id
    and status <> 'paid'
  returning * into v_payment;

  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'ALREADY_PAID',
      'error', 'This charging session has already been paid.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'payment_id', v_payment.id,
    'status', v_payment.status,
    'total_amount', v_payment.total_amount,
    'transaction_id', v_payment.transaction_id,
    'paid_at', v_payment.paid_at
  );
end;
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.charging_payment_finish(uuid, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.charging_payment_finish(uuid, uuid, boolean, text) to service_role;
