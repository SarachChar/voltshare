// refund-booking-fee
//
// Refunds a booking's fee and cancels the booking when the charger turned out
// to be unavailable at plug-in (ocpp-status -> Unavailable). The SQL function
// refund_booking_fee re-checks that the charger is really unavailable, so this
// can't be used to cancel for free.
//
// The request / response shapes mimic Stripe's Refund API, wrapped in the
// app's { success, data } envelope. The charge to refund is the booking fee's
// charge id (booking_fee.transaction_id).
//
// MOCK: no real money moves; a Stripe-style refund id ("re_...") is generated
// and stored in booking_fee.refund_transaction_id.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Amounts follow Stripe: smallest currency unit (satang), so 50 THB = 5000.
// Only full refunds: amount (optional) must equal the whole booking fee.
//
// Request:
//   {
//     "charge": "ch_...",
//     "amount": 5000,                       // optional, default = full fee
//     "reason": "requested_by_customer",    // optional
//     "metadata": { "reservation_id": "<uuid>" }
//   }
//
// Response (success, 200):
//   { "success": true, "data": {
//       "id": "re_...", "object": "refund", "amount": 5000,
//       "charge": "ch_...", "created": 1793700000, "currency": "thb",
//       "reason": "requested_by_customer", "status": "succeeded",
//       "failure_reason": null,
//       "metadata": { "reservation_id": "<uuid>" } } }
//
// Response (error):
//   { "success": false, "data": {
//       "type": "invalid_request_error", "code": "charger_available",
//       "message": "...", "param": null } }
//
// Errors (HTTP status / type / code / param):
//   400 invalid_request_error parameter_missing | parameter_invalid_integer |
//       parameter_invalid_string  (param = field)
//   400 invalid_request_error charge_mismatch        (charge isn't this reservation's; not a Stripe code)
//   401 authentication_error  null
//   403 invalid_request_error null                   (reservation not yours)
//   404 invalid_request_error resource_missing       (charge | metadata.reservation_id)
//   405 invalid_request_error null                   (non-POST)
//   409 invalid_request_error charge_already_refunded
//   409 invalid_request_error reservation_not_active (not a Stripe code)
//   409 invalid_request_error charger_available      (not a Stripe code)
//   409 invalid_request_error amount_mismatch        (param amount; not a Stripe code)
//   500 api_error             null
//
// Deploy: supabase functions deploy refund-booking-fee --use-api

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { corsHeaders, json, readJson } from "../_shared/http.ts";
import { adminClient, callRpc, getUserId } from "../_shared/supabase.ts";

type StripeErrorType =
  | "api_error"
  | "authentication_error"
  | "invalid_request_error";

type StripeError = {
  type: StripeErrorType;
  code: string | null;
  message: string;
  param: string | null;
};

const REFUND_REASONS = ["duplicate", "fraudulent", "requested_by_customer"];

/** Random id in Stripe's style, e.g. "re_3QmockAbCdEfGh0a1B2c3D4e". */
function stripeId(prefix: "re"): string {
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

/** Maps an error_code from the refund_booking_fee SQL function. */
function rpcError(errorCode: string | undefined, message: string): Response {
  switch (errorCode) {
    case "RESERVATION_NOT_FOUND":
      return invalidRequest(404, "resource_missing", message, "metadata.reservation_id");
    case "NOT_OWNER":
      return invalidRequest(403, null, message, "metadata.reservation_id");
    case "RESERVATION_NOT_ACTIVE":
      return invalidRequest(409, "reservation_not_active", message);
    case "CHARGER_AVAILABLE":
      return invalidRequest(409, "charger_available", message);
    case "ALREADY_REFUNDED":
      return invalidRequest(409, "charge_already_refunded", message, "charge");
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

type RefundRequest = {
  charge: string;
  amount: number;
  reason: string;
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

  const body = await readJson<RefundRequest>(req);
  const { charge, amount } = body;
  const reason = body.reason ?? null;
  const metadata = body.metadata && typeof body.metadata === "object"
    ? (body.metadata as Record<string, unknown>)
    : {};
  const reservationId = metadata.reservation_id;

  // ---- Validate the request (Stripe-style parameter errors) ----
  if (!isNonEmptyString(charge)) {
    return invalidRequest(400, "parameter_missing", "Missing required param: charge.", "charge");
  }
  if (
    amount !== undefined && amount !== null &&
    (typeof amount !== "number" || !Number.isInteger(amount) || amount < 0)
  ) {
    return invalidRequest(
      400,
      "parameter_invalid_integer",
      "amount must be a non-negative integer in satang.",
      "amount",
    );
  }
  if (reason !== null && !REFUND_REASONS.includes(String(reason))) {
    return invalidRequest(
      400,
      "parameter_invalid_string",
      `Invalid reason: must be one of ${REFUND_REASONS.join(", ")}.`,
      "reason",
    );
  }
  if (!isNonEmptyString(reservationId)) {
    return invalidRequest(
      400,
      "parameter_missing",
      "Missing required param: metadata[reservation_id].",
      "metadata.reservation_id",
    );
  }

  // ---- Reservation must exist and belong to the caller ----
  // (refund_booking_fee checks this again; done here first so a stranger
  // can't probe charge ids of other users' bookings.)
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
    return rpcError("RESERVATION_NOT_FOUND", `No such reservation: '${reservationId}'.`);
  }
  if (reservation.user_id !== userId) {
    return rpcError("NOT_OWNER", "This reservation belongs to another user.");
  }

  // ---- The charge must be this reservation's booking fee ----
  const { data: fee, error: feeError } = await admin
    .from("booking_fee")
    .select("id, reservation_id, amount")
    .eq("transaction_id", charge)
    .maybeSingle();
  if (feeError) {
    console.error("booking_fee lookup failed", feeError);
    return apiError("Database error.");
  }
  if (!fee) {
    return invalidRequest(404, "resource_missing", `No such charge: '${charge}'.`, "charge");
  }
  if (fee.reservation_id !== reservationId) {
    return invalidRequest(
      400,
      "charge_mismatch",
      "This charge doesn't belong to the given reservation.",
      "charge",
    );
  }

  // ---- Full refunds only ----
  const feeSatang = Math.round(Number(fee.amount) * 100);
  if (amount !== undefined && amount !== null && amount !== feeSatang) {
    return invalidRequest(
      409,
      "amount_mismatch",
      "Only full refunds are supported: amount must equal the booking fee.",
      "amount",
    );
  }

  // Simulated refund latency.
  await new Promise((resolve) => setTimeout(resolve, 600));

  const result = await callRpc(admin, "refund_booking_fee", {
    p_reservation_id: reservationId,
    p_user_id: userId,
    p_refund_transaction_id: stripeId("re"),
  });
  if (!result.ok) {
    return rpcError(result.error_code, result.error ?? "Rejected.");
  }

  return json({
    success: true,
    data: {
      id: result.refund_transaction_id,
      object: "refund",
      amount: Math.round(Number(result.refunded_amount) * 100),
      charge,
      created: toUnixSeconds(result.refunded_at),
      currency: "thb",
      reason,
      status: "succeeded",
      failure_reason: null,
      metadata,
    },
  });
});
