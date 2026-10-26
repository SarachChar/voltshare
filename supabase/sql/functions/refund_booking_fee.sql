-- =============================================================================
-- refund_booking_fee
-- -----------------------------------------------------------------------------
-- Refunds the booking fee and cancels the reservation when the charger is
-- unavailable at plug-in (ocpp-status reported Unavailable). The check is
-- repeated here so a driver can't call the refund endpoint to cancel for
-- free while the charger is fine.
--
-- RULES (checked in this order; first failure is returned)
--   - reservation exists                          RESERVATION_NOT_FOUND
--   - belongs to p_user_id                        NOT_OWNER
--   - status 'confirmed' and not started          RESERVATION_NOT_ACTIVE
--     (started_at is null)
--   - charger is unavailable                      CHARGER_AVAILABLE
--     (chargers.mock_error_code is set)
--   - fee not refunded already                    ALREADY_REFUNDED
--
-- ON SUCCESS (one transaction, reservation row locked FOR UPDATE)
--   - booking_fee: status 'refunded', refunded_at, refund_transaction_id
--     (transaction_id keeps the original payment's id)
--   - reservations: status 'cancelled'
--   A reservation without a booking_fee row is still cancelled (amount 0).
--
-- RETURNS jsonb
--   { "ok": true, "booking_fee_id", "refunded_amount", "refund_transaction_id",
--     "refunded_at", "reservation_status" }
--   { "ok": false, "error_code": "...", "error": "..." }
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor AFTER the booking_fee ALTER (refunded_at,
--   refund_transaction_id). CREATE OR REPLACE, so re-running is safe.
--
-- CALLED BY
--   The refund-booking-fee edge function (service role only).
-- =============================================================================

create or replace function public.refund_booking_fee(
  p_reservation_id uuid,
  p_user_id uuid,
  p_refund_transaction_id text
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_res        reservations%rowtype;
  v_error_code text;
  v_fee        booking_fee%rowtype;
  v_now        timestamptz := now();
begin
  select * into v_res from reservations where id = p_reservation_id for update;

  if not found then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_NOT_FOUND',
      'error', 'Reservation not found.');
  end if;

  if v_res.user_id <> p_user_id then
    return jsonb_build_object('ok', false, 'error_code', 'NOT_OWNER',
      'error', 'This reservation belongs to another user.');
  end if;

  if v_res.status <> 'confirmed' or v_res.started_at is not null then
    return jsonb_build_object('ok', false, 'error_code', 'RESERVATION_NOT_ACTIVE',
      'error', 'This booking can no longer be refunded.');
  end if;

  select nullif(btrim(mock_error_code), '') into v_error_code
  from chargers where id = v_res.charger_id;

  if v_error_code is null then
    return jsonb_build_object('ok', false, 'error_code', 'CHARGER_AVAILABLE',
      'error', 'The charger is available, so the booking fee is not refundable.');
  end if;

  select * into v_fee from booking_fee where reservation_id = v_res.id for update;

  if found and v_fee.status = 'refunded' then
    return jsonb_build_object('ok', false, 'error_code', 'ALREADY_REFUNDED',
      'error', 'This booking fee has already been refunded.');
  end if;

  if found then
    update booking_fee
    set status = 'refunded',
        refunded_at = v_now,
        refund_transaction_id = p_refund_transaction_id
    where id = v_fee.id
    returning * into v_fee;
  end if;

  update reservations set status = 'cancelled' where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'booking_fee_id', v_fee.id,
    'refunded_amount', coalesce(v_fee.amount, 0),
    'refund_transaction_id', v_fee.refund_transaction_id,
    'refunded_at', coalesce(v_fee.refunded_at, v_now),
    'reservation_status', 'cancelled'
  );
end;
$$;

-- Only the service role (edge functions) may call this.
revoke execute on function public.refund_booking_fee(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.refund_booking_fee(uuid, uuid, text) to service_role;
