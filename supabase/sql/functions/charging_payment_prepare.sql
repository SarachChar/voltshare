-- =============================================================================
-- charging_payment_prepare
-- -----------------------------------------------------------------------------
--   Validates a pay attempt and returns what the edge function needs to run
--   the (mock) card charge. Amounts come from the stored bill, never from the
--   app.
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

create or replace function public.charging_payment_prepare(
  p_session_id uuid,
  p_user_id uuid,
  p_payment_method_id uuid
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_owner    uuid;
  v_payment  session_payments%rowtype;
  v_card     payment_methods%rowtype;
begin
  select r.user_id into v_owner
  from charging_sessions s
  join reservations r on r.id = s.reservation_id
  where s.id = p_session_id;

  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'SESSION_NOT_FOUND',
      'error', 'Charging session not found.');
  end if;

  if v_owner <> p_user_id then
    return jsonb_build_object('ok', false, 'error_code', 'NOT_OWNER',
      'error', 'This charging session belongs to another user.');
  end if;

  select * into v_payment from session_payments where session_id = p_session_id;
  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'SESSION_NOT_FOUND',
      'error', 'This charging session has no bill yet.');
  end if;

  if v_payment.status = 'paid' then
    return jsonb_build_object('ok', false, 'error_code', 'ALREADY_PAID',
      'error', 'This charging session has already been paid.');
  end if;

  select * into v_card
  from payment_methods
  where id = p_payment_method_id and user_id = p_user_id;

  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_PAYMENT_METHOD',
      'error', 'Payment method not found.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'payment_id', v_payment.id,
    'amount', v_payment.total_amount,
    'card_last4', right(regexp_replace(v_card.card_number, '\s', '', 'g'), 4)
  );
end;
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.charging_payment_prepare(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.charging_payment_prepare(uuid, uuid, uuid) to service_role;
