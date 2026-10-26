// refund-booking-fee
//
// Refunds a booking's fee and cancels the booking when the charger turned out
// to be unavailable at plug-in (ocpp-status -> Unavailable). The SQL function
// refund_booking_fee re-checks that the charger is really unavailable, so this
// can't be used to cancel for free.
//
// MOCK: no real money moves; a mock refund id is generated.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Request:  { "reservationId": "<uuid>" }
// Response:
//   { "success": true, "data": {
//       "status": "refunded", "bookingFeeId": "...", "refundedAmount": 10,
//       "transactionId": "mock_refund_...", "refundedAt": "...",
//       "reservationStatus": "cancelled" } }
//   { "success": false, "data": { "errorCode": "CHARGER_AVAILABLE", "error": "..." } }
//
// errorCodes: INVALID_REQUEST, UNAUTHORIZED, RESERVATION_NOT_FOUND, NOT_OWNER,
//   RESERVATION_NOT_ACTIVE, CHARGER_AVAILABLE, ALREADY_REFUNDED, INTERNAL_ERROR
//
// Deploy: supabase functions deploy refund-booking-fee --use-api

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, callRpc, getUserId } from "../_shared/supabase.ts";

function mockRefundId(): string {
  const rand = Math.random().toString(36).slice(2, 10);
  return `mock_refund_${Date.now()}_${rand}`;
}

Deno.serve(async (req: Request) => {
  const early = preflight(req);
  if (early) return early;

  const admin = adminClient();
  const userId = await getUserId(req, admin);
  if (!userId) return fail("UNAUTHORIZED", "Please sign in.");

  const { reservationId } = await readJson<{ reservationId: string }>(req);
  if (typeof reservationId !== "string" || reservationId.length === 0) {
    return fail("INVALID_REQUEST", "reservationId is required.");
  }

  // Simulated refund latency.
  await new Promise((resolve) => setTimeout(resolve, 600));

  const result = await callRpc(admin, "refund_booking_fee", {
    p_reservation_id: reservationId,
    p_user_id: userId,
    p_refund_transaction_id: mockRefundId(),
  });
  if (!result.ok) {
    return fail(result.error_code ?? "INTERNAL_ERROR", result.error ?? "Rejected.");
  }

  return ok({
    status: "refunded",
    bookingFeeId: result.booking_fee_id,
    refundedAmount: result.refunded_amount,
    transactionId: result.refund_transaction_id,
    refundedAt: result.refunded_at,
    reservationStatus: result.reservation_status,
  });
});
