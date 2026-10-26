// pay-charging-session
//
// Pays the bill of a finished charging session with one of the driver's saved
// cards. The bill itself is computed in SQL when the session stops; the app
// sends the amount it showed the driver, which must match the bill
// (AMOUNT_MISMATCH otherwise), so the driver is never charged something
// different from what the Pay button said.
//
// MOCK: no real money moves. Same rule as mock-payment: a card ending in
// "0000" is declined, any other card succeeds.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Request:  { "sessionId": "<uuid>", "paymentMethodId": "<uuid>", "amount": 79.84 }
// Response:
//   { "success": true, "data": {
//       "status": "paid", "paymentId": "...", "totalAmount": 79.84,
//       "transactionId": "mock_txn_...", "paidAt": "..." } }
//   { "success": false, "data": { "errorCode": "PAYMENT_DECLINED", "error": "..." } }
//
// errorCodes: INVALID_REQUEST, UNAUTHORIZED, SESSION_NOT_FOUND, NOT_OWNER,
//   ALREADY_PAID, INVALID_PAYMENT_METHOD, AMOUNT_MISMATCH, PAYMENT_DECLINED,
//   INTERNAL_ERROR
//
// Deploy: supabase functions deploy pay-charging-session

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, callRpc, getUserId } from "../_shared/supabase.ts";

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

  const { sessionId, paymentMethodId, amount } = await readJson<{
    sessionId: string;
    paymentMethodId: string;
    amount: number;
  }>(req);
  if (
    typeof sessionId !== "string" || sessionId.length === 0 ||
    typeof paymentMethodId !== "string" || paymentMethodId.length === 0 ||
    typeof amount !== "number" || !Number.isFinite(amount) || amount < 0
  ) {
    return fail(
      "INVALID_REQUEST",
      "sessionId, paymentMethodId and amount are required.",
    );
  }

  const prepared = await callRpc(admin, "charging_payment_prepare", {
    p_session_id: sessionId,
    p_user_id: userId,
    p_payment_method_id: paymentMethodId,
  });
  if (!prepared.ok) {
    return fail(prepared.error_code ?? "INTERNAL_ERROR", prepared.error ?? "Rejected.");
  }

  // Compare in satang to avoid float rounding (79.84 vs 79.840000001).
  const billSatang = Math.round(Number(prepared.amount) * 100);
  if (Math.round(amount * 100) !== billSatang) {
    return fail(
      "AMOUNT_MISMATCH",
      "The amount doesn't match this session's bill. Please refresh and try again.",
    );
  }

  // Mock card charge (simulated latency, deterministic outcome).
  await new Promise((resolve) => setTimeout(resolve, 600));
  const declined = prepared.card_last4 === "0000";
  const transactionId = declined ? null : mockTransactionId();

  const finished = await callRpc(admin, "charging_payment_finish", {
    p_payment_id: prepared.payment_id,
    p_payment_method_id: paymentMethodId,
    p_success: !declined,
    p_transaction_id: transactionId,
  });
  if (!finished.ok) {
    return fail(finished.error_code ?? "INTERNAL_ERROR", finished.error ?? "Rejected.");
  }

  if (declined) {
    return fail(
      "PAYMENT_DECLINED",
      "Payment declined: insufficient funds. Try another card.",
    );
  }

  return ok({
    status: "paid",
    paymentId: finished.payment_id,
    totalAmount: finished.total_amount,
    transactionId: finished.transaction_id,
    paidAt: finished.paid_at,
  });
});
