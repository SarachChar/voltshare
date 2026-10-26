// pay-booking-fee
//
// Pays the booking fee of a just-created reservation with one of the
// driver's saved cards, and records it in booking_fee (1-1 with the
// reservation). Replaces mock-payment + the app's own booking_fee insert.
//
// MOCK: no real money moves. A card ending in "0000" is declined, any other
// card succeeds. On decline nothing is written; the app rolls back (deletes)
// the reservation.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Request:  { "reservationId": "<uuid>", "paymentMethodId": "<uuid>", "amount": 10 }
// Response:
//   { "success": true, "data": {
//       "status": "paid", "bookingFeeId": "...", "totalAmount": 10,
//       "transactionId": "mock_txn_...", "paidAt": "..." } }
//   { "success": false, "data": { "errorCode": "PAYMENT_DECLINED", "error": "..." } }
//
// errorCodes: INVALID_REQUEST, UNAUTHORIZED, RESERVATION_NOT_FOUND, NOT_OWNER,
//   INVALID_PAYMENT_METHOD, ALREADY_PAID, PAYMENT_DECLINED, INTERNAL_ERROR
//
// Deploy: supabase functions deploy pay-booking-fee --use-api

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, getUserId } from "../_shared/supabase.ts";

function mockTransactionId(): string {
  const rand = Math.random().toString(36).slice(2, 10);
  return `mock_txn_${Date.now()}_${rand}`;
}

Deno.serve(async (req: Request) => {
  const early = preflight(req);
  if (early) return early;

  const admin = adminClient();
  const userId = await getUserId(req, admin);
  if (!userId) return fail("UNAUTHORIZED", "Please sign in.");

  const { reservationId, paymentMethodId, amount } = await readJson<{
    reservationId: string;
    paymentMethodId: string;
    amount: number;
  }>(req);
  if (
    typeof reservationId !== "string" || reservationId.length === 0 ||
    typeof paymentMethodId !== "string" || paymentMethodId.length === 0 ||
    typeof amount !== "number" || !Number.isInteger(amount) || amount < 0
  ) {
    return fail(
      "INVALID_REQUEST",
      "reservationId, paymentMethodId and a whole-baht amount are required.",
    );
  }

  // Reservation must exist and belong to the caller.
  const { data: reservation, error: resError } = await admin
    .from("reservations")
    .select("id, user_id")
    .eq("id", reservationId)
    .maybeSingle();
  if (resError) {
    console.error("reservation lookup failed", resError);
    return fail("INTERNAL_ERROR", "Database error.");
  }
  if (!reservation) {
    return fail("RESERVATION_NOT_FOUND", "Reservation not found.");
  }
  if (reservation.user_id !== userId) {
    return fail("NOT_OWNER", "This reservation belongs to another user.");
  }

  // Card must belong to the caller.
  const { data: card, error: cardError } = await admin
    .from("payment_methods")
    .select("id, card_number")
    .eq("id", paymentMethodId)
    .eq("user_id", userId)
    .maybeSingle();
  if (cardError) {
    console.error("card lookup failed", cardError);
    return fail("INTERNAL_ERROR", "Database error.");
  }
  if (!card) {
    return fail("INVALID_PAYMENT_METHOD", "Payment method not found.");
  }

  // Already paid?
  const { data: existing } = await admin
    .from("booking_fee")
    .select("id")
    .eq("reservation_id", reservationId)
    .maybeSingle();
  if (existing) {
    return fail("ALREADY_PAID", "This booking fee has already been paid.");
  }

  // Mock card charge (simulated latency, deterministic outcome).
  await new Promise((resolve) => setTimeout(resolve, 600));
  const last4 = String(card.card_number ?? "").replace(/\s/g, "").slice(-4);
  if (last4 === "0000") {
    return fail(
      "PAYMENT_DECLINED",
      "Payment declined: insufficient funds. Try another card.",
    );
  }

  const transactionId = mockTransactionId();
  const { data: fee, error: insertError } = await admin
    .from("booking_fee")
    .insert({
      reservation_id: reservationId,
      payment_method_id: paymentMethodId,
      amount,
      status: "paid",
      transaction_id: transactionId,
    })
    .select("id, amount, transaction_id, created_at")
    .single();

  if (insertError) {
    // 23505 = unique_violation on reservation_id (paid concurrently).
    if (insertError.code === "23505") {
      return fail("ALREADY_PAID", "This booking fee has already been paid.");
    }
    console.error("booking_fee insert failed", insertError);
    return fail("INTERNAL_ERROR", "Couldn't record the payment.");
  }

  return ok({
    status: "paid",
    bookingFeeId: fee.id,
    totalAmount: fee.amount,
    transactionId: fee.transaction_id,
    paidAt: fee.created_at,
  });
});
