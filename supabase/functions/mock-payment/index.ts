// Mock payment edge function.
//
// Simulates charging a saved card for a booking fee. NO real money moves and no
// real gateway is called. The outcome is deterministic so demos can show both
// paths:
//   - card number ending in "0000" -> payment FAILS (insufficient_funds)
//   - any other card              -> payment SUCCEEDS
//
// Request body (JSON):
//   {
//     "card_last4": "4242",       // last 4 digits of the chosen card
//     "amount": 40,                // booking fee in THB
//     "reservation_ref": "..."     // optional: client reference for the booking
//   }
//
// Response (JSON):
//   success -> { "status": "success", "transaction_id": "mock_txn_...", "amount": 40 }
//   failure -> { "status": "failed",  "reason": "insufficient_funds" }
//
// Deploy with:  supabase functions deploy mock-payment

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Simple pseudo-unique id for the mock transaction. */
function mockTransactionId(): string {
  const rand = Math.random().toString(36).slice(2, 10);
  return `mock_txn_${Date.now()}_${rand}`;
}

Deno.serve(async (req: Request) => {
  // CORS preflight.
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ status: "failed", reason: "method_not_allowed" }, 405);
  }

  let payload: {
    card_last4?: string;
    amount?: number;
    reservation_ref?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ status: "failed", reason: "invalid_request" }, 400);
  }

  const cardLast4 = (payload.card_last4 ?? "").trim();
  const amount = payload.amount;

  // Basic validation.
  if (cardLast4.length !== 4 || typeof amount !== "number" || amount <= 0) {
    return json({ status: "failed", reason: "invalid_request" }, 400);
  }

  // Simulate a little processing latency.
  await new Promise((resolve) => setTimeout(resolve, 600));

  // Deterministic outcome: cards ending in 0000 always decline.
  if (cardLast4 === "0000") {
    return json({ status: "failed", reason: "insufficient_funds" });
  }

  return json({
    status: "success",
    transaction_id: mockTransactionId(),
    amount,
  });
});
