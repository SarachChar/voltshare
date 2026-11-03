// pay-charging-session
//
// Pays the bill of a finished charging session with one of the driver's saved
// cards. The bill itself is computed in SQL when the session stops; the app
// sends the amount it showed the driver, which must match the bill
// (amount_mismatch otherwise), so the driver is never charged something
// different from what the Pay button said.
//
// The request / response shapes mimic Stripe's PaymentIntent API (create +
// confirm in one call), wrapped in the app's { success, data } envelope.
//
// MOCK: no real money moves. A card ending in "0000" is declined, any other
// card succeeds. Both outcomes are recorded by charging_payment_finish
// ('paid' / 'failed'), with the charge id in session_payments.transaction_id.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Amounts follow Stripe: smallest currency unit (satang), so 79.84 THB = 7984.
//
// Request:
//   {
//     "amount": 7984,
//     "currency": "thb",
//     "payment_method": "<payment_methods.id>",
//     "description": "charging session #<sessionId>",
//     "receipt_email": "driver@mail.com",
//     "metadata": { "sessionId": "<uuid>" }
//   }
//
// Response (success, 200):
//   { "success": true, "data": {
//       "id": "pi_...", "object": "payment_intent", "amount": 7984,
//       "currency": "thb", "status": "succeeded", "created": 1793685460,
//       "payment_method": "<uuid>", "latest_charge": "ch_...",
//       "description": "charging session #<sessionId>",
//       "metadata": { "sessionId": "<uuid>", "paymentId": "<uuid>" } } }
//   receipt_email is accepted in the request but not echoed back.
//
// Response (error):
//   { "success": false, "data": {
//       "type": "card_error", "code": "card_declined",
//       "decline_code": "insufficient_funds",
//       "message": "Your card has insufficient funds.",
//       "param": null, "charge": "ch_..." } }
//
// Errors (HTTP status / type / code / param):
//   400 invalid_request_error parameter_missing | parameter_invalid_integer |
//       parameter_invalid_string  (param = field)
//   401 authentication_error  null
//   402 card_error            card_declined (decline_code insufficient_funds)
//   403 invalid_request_error null                  (session not yours)
//   404 invalid_request_error resource_missing      (metadata.sessionId | payment_method)
//   405 invalid_request_error null                  (non-POST)
//   409 invalid_request_error payment_intent_unexpected_state (already paid)
//   409 invalid_request_error amount_mismatch       (param amount; not a Stripe code)
//   500 api_error             null
//
// Deploy: supabase functions deploy pay-charging-session --use-api

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { corsHeaders, json, readJson } from "../_shared/http.ts";
import { adminClient, callRpc, getUserId } from "../_shared/supabase.ts";

type StripeErrorType =
  | "api_error"
  | "authentication_error"
  | "card_error"
  | "invalid_request_error";

type StripeError = {
  type: StripeErrorType;
  code: string | null;
  message: string;
  param: string | null;
  decline_code?: string;
  charge?: string;
};

/** Random id in Stripe's style, e.g. "pi_3QmockAbCdEfGh0a1B2c3D4e". */
function stripeId(prefix: "pi" | "ch"): string {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const rand = Array.from(bytes, (b) => chars[b % chars.length]).join("");
  return `${prefix}_3Qmock${rand}`;
}

function stripeError(status: number, error: StripeError): Response {
  return json({ success: false, data: error }, status);
}

function invalidRequest(
  status: number,
  code: string | null,
  message: string,
  param: string | null = null,
): Response {
  return stripeError(status, {
    type: "invalid_request_error",
    code,
    message,
    param,
  });
}

function apiError(message: string): Response {
  return stripeError(500, {
    type: "api_error",
    code: null,
    message,
    param: null,
  });
}

/** Maps an error_code from the charging_payment_* SQL functions. */
function rpcError(errorCode: string | undefined, message: string): Response {
  switch (errorCode) {
    case "SESSION_NOT_FOUND":
      return invalidRequest(404, "resource_missing", message, "metadata.sessionId");
    case "NOT_OWNER":
      return invalidRequest(403, null, message, "metadata.sessionId");
    case "INVALID_PAYMENT_METHOD":
      return invalidRequest(404, "resource_missing", message, "payment_method");
    case "ALREADY_PAID":
      return invalidRequest(409, "payment_intent_unexpected_state", message);
    default:
      return apiError(message);
  }
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}

function toUnixSeconds(iso: unknown): number {
  const ms = new Date(String(iso ?? "")).getTime();
  return Math.floor((Number.isFinite(ms) ? ms : Date.now()) / 1000);
}

type PaymentIntentRequest = {
  amount: number;
  currency: string;
  payment_method: string;
  description: string;
  receipt_email: string;
  metadata: Record<string, unknown>;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return invalidRequest(405, null, "Use POST.");
  }

  const admin = adminClient();
  const userId = await getUserId(req, admin);
  if (!userId) {
    return stripeError(401, {
      type: "authentication_error",
      code: null,
      message: "Please sign in.",
      param: null,
    });
  }

  const body = await readJson<PaymentIntentRequest>(req);
  const { amount, currency, payment_method: paymentMethodId } = body;
  const description = typeof body.description === "string"
    ? body.description
    : null;
  const metadata = body.metadata && typeof body.metadata === "object"
    ? (body.metadata as Record<string, unknown>)
    : {};
  const sessionId = metadata.sessionId;

  // ---- Validate the request (Stripe-style parameter errors) ----
  if (amount === undefined || amount === null) {
    return invalidRequest(400, "parameter_missing", "Missing required param: amount.", "amount");
  }
  if (typeof amount !== "number" || !Number.isInteger(amount) || amount < 0) {
    return invalidRequest(
      400,
      "parameter_invalid_integer",
      "amount must be a non-negative integer in satang.",
      "amount",
    );
  }
  if (!isNonEmptyString(currency)) {
    return invalidRequest(400, "parameter_missing", "Missing required param: currency.", "currency");
  }
  if (currency.toLowerCase() !== "thb") {
    return invalidRequest(
      400,
      "parameter_invalid_string",
      `Invalid currency: ${currency}. Only thb is supported.`,
      "currency",
    );
  }
  if (!isNonEmptyString(paymentMethodId)) {
    return invalidRequest(
      400,
      "parameter_missing",
      "Missing required param: payment_method.",
      "payment_method",
    );
  }
  if (!isNonEmptyString(sessionId)) {
    return invalidRequest(
      400,
      "parameter_missing",
      "Missing required param: metadata[sessionId].",
      "metadata.sessionId",
    );
  }

  // ---- Ownership, bill, card checks (SQL) ----
  const prepared = await callRpc(admin, "charging_payment_prepare", {
    p_session_id: sessionId,
    p_user_id: userId,
    p_payment_method_id: paymentMethodId,
  });
  if (!prepared.ok) {
    return rpcError(prepared.error_code, prepared.error ?? "Rejected.");
  }

  // The bill is numeric(10,2) baht; compare in satang.
  const billSatang = Math.round(Number(prepared.amount) * 100);
  if (amount !== billSatang) {
    return invalidRequest(
      409,
      "amount_mismatch",
      "The amount doesn't match this session's bill. Please refresh and try again.",
      "amount",
    );
  }

  // ---- Mock card charge (simulated latency, deterministic outcome) ----
  await new Promise((resolve) => setTimeout(resolve, 600));
  const declined = prepared.card_last4 === "0000";
  const chargeId = stripeId("ch");

  const finished = await callRpc(admin, "charging_payment_finish", {
    p_payment_id: prepared.payment_id,
    p_payment_method_id: paymentMethodId,
    p_success: !declined,
    p_transaction_id: chargeId,
  });
  if (!finished.ok) {
    return rpcError(finished.error_code, finished.error ?? "Rejected.");
  }

  if (declined) {
    return stripeError(402, {
      type: "card_error",
      code: "card_declined",
      decline_code: "insufficient_funds",
      message: "Your card has insufficient funds.",
      param: null,
      charge: chargeId,
    });
  }

  return json({
    success: true,
    data: {
      id: stripeId("pi"), // not stored
      object: "payment_intent",
      amount: Math.round(Number(finished.total_amount) * 100),
      currency: "thb",
      status: "succeeded",
      created: toUnixSeconds(finished.paid_at),
      payment_method: paymentMethodId,
      latest_charge: finished.transaction_id,
      description,
      metadata: { ...metadata, paymentId: finished.payment_id },
    },
  });
});
