// pay-booking-fee
//
// Pays the booking fee of a just-created reservation with one of the
// driver's saved cards, and records it in booking_fee (1-1 with the
// reservation).
//
// The request / response shapes mimic Stripe's PaymentIntent API (create +
// confirm in one call), wrapped in the app's { success, data } envelope.
//
// MOCK: no real money moves. A card ending in "0000" is declined, any other
// card succeeds. On decline nothing is written; the app rolls back (deletes)
// the reservation.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Amounts follow Stripe: smallest currency unit (satang), so 150 THB = 15000.
// booking_fee.amount stays in whole baht, so amount must be a multiple of 100.
//
// Request:
//   {
//     "amount": 15000,
//     "currency": "thb",
//     "payment_method": "<payment_methods.id>",
//     "description": "reservation fee #<reservationId>",
//     "receipt_email": "driver@mail.com",
//     "metadata": { "reservationId": "<uuid>" }
//   }
//
// Response (success, 200):
//   { "success": true, "data": {
//       "id": "pi_...", "object": "payment_intent", "amount": 15000,
//       "currency": "thb", "status": "succeeded", "created": 1793685460,
//       "payment_method": "<uuid>", "latest_charge": "ch_...",
//       "description": "reservation fee #<reservationId>",
//       "metadata": { "reservationId": "<uuid>", "bookingFeeId": "<uuid>" } } }
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
//       invalid_charge_amount | parameter_invalid_string  (param = field)
//   401 authentication_error  null
//   402 card_error            card_declined (decline_code insufficient_funds)
//   403 invalid_request_error null                  (reservation not yours)
//   404 invalid_request_error resource_missing      (metadata.reservationId | payment_method)
//   405 invalid_request_error null                  (non-POST)
//   409 invalid_request_error payment_intent_unexpected_state (already paid)
//   500 api_error             null
//
// Deploy: supabase functions deploy pay-booking-fee --use-api

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { corsHeaders, json, readJson } from "../_shared/http.ts";
import { adminClient, getUserId } from "../_shared/supabase.ts";

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

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
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
  const reservationId = metadata.reservationId;

  // ---- Validate the request (Stripe-style parameter errors) ----
  if (amount === undefined || amount === null) {
    return invalidRequest(400, "parameter_missing", "Missing required param: amount.", "amount");
  }
  if (typeof amount !== "number" || !Number.isInteger(amount)) {
    return invalidRequest(400, "parameter_invalid_integer", "Invalid integer: amount.", "amount");
  }
  if (amount < 0 || amount % 100 !== 0) {
    return invalidRequest(
      400,
      "invalid_charge_amount",
      "amount must be a non-negative whole-baht value in satang (multiple of 100).",
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
  if (!isNonEmptyString(reservationId)) {
    return invalidRequest(
      400,
      "parameter_missing",
      "Missing required param: metadata[reservationId].",
      "metadata.reservationId",
    );
  }

  // ---- Reservation must exist and belong to the caller ----
  const { data: reservation, error: resError } = await admin
    .from("reservations")
    .select("id, user_id")
    .eq("id", reservationId)
    .maybeSingle();
  if (resError) {
    console.error("reservation lookup failed", resError);
    return apiError("Database error.");
  }
  if (!reservation) {
    return invalidRequest(
      404,
      "resource_missing",
      `No such reservation: '${reservationId}'.`,
      "metadata.reservationId",
    );
  }
  if (reservation.user_id !== userId) {
    return invalidRequest(
      403,
      null,
      "This reservation belongs to another user.",
      "metadata.reservationId",
    );
  }

  // ---- Card must belong to the caller ----
  const { data: card, error: cardError } = await admin
    .from("payment_methods")
    .select("id, card_number")
    .eq("id", paymentMethodId)
    .eq("user_id", userId)
    .maybeSingle();
  if (cardError) {
    console.error("card lookup failed", cardError);
    return apiError("Database error.");
  }
  if (!card) {
    return invalidRequest(
      404,
      "resource_missing",
      `No such PaymentMethod: '${paymentMethodId}'.`,
      "payment_method",
    );
  }

  // ---- Already paid? ----
  const { data: existing } = await admin
    .from("booking_fee")
    .select("id")
    .eq("reservation_id", reservationId)
    .maybeSingle();
  if (existing) {
    return invalidRequest(
      409,
      "payment_intent_unexpected_state",
      "This booking fee has already been paid.",
    );
  }

  // ---- Mock card charge (simulated latency, deterministic outcome) ----
  await new Promise((resolve) => setTimeout(resolve, 600));
  const chargeId = stripeId("ch");
  const last4 = String(card.card_number ?? "").replace(/\s/g, "").slice(-4);
  if (last4 === "0000") {
    // Declined charges aren't recorded; the id only appears in the response.
    return stripeError(402, {
      type: "card_error",
      code: "card_declined",
      decline_code: "insufficient_funds",
      message: "Your card has insufficient funds.",
      param: null,
      charge: chargeId,
    });
  }

  const { data: fee, error: insertError } = await admin
    .from("booking_fee")
    .insert({
      reservation_id: reservationId,
      payment_method_id: paymentMethodId,
      amount: amount / 100, // satang -> whole baht
      status: "paid",
      transaction_id: chargeId,
    })
    .select("id, amount, transaction_id, created_at")
    .single();

  if (insertError) {
    // 23505 = unique_violation on reservation_id (paid concurrently).
    if (insertError.code === "23505") {
      return invalidRequest(
        409,
        "payment_intent_unexpected_state",
        "This booking fee has already been paid.",
      );
    }
    console.error("booking_fee insert failed", insertError);
    return apiError("Couldn't record the payment.");
  }

  return json({
    success: true,
    data: {
      id: stripeId("pi"), // not stored
      object: "payment_intent",
      amount: Number(fee.amount) * 100,
      currency: "thb",
      status: "succeeded",
      created: Math.floor(new Date(fee.created_at).getTime() / 1000),
      payment_method: paymentMethodId,
      latest_charge: fee.transaction_id,
      description,
      metadata: { ...metadata, bookingFeeId: fee.id },
    },
  });
});
