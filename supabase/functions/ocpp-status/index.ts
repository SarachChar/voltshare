// ocpp-status
//
// App -> CSMS: "what is this charger's connector status?" Called when the
// driver taps "I've Plugged In", before the Charging Session screen opens.
// In real OCPP the CSMS would answer from the charger's latest
// StatusNotification. Here the charger is mocked with a single switch:
//
//   chargers.mock_error_code is set  -> status "Unavailable", errorCode = it
//   chargers.mock_error_code is null -> status "Available",   errorCode "NoError"
//
// Set / clear the switch for demos:
//   update chargers set mock_error_code = 'GroundFailure' where id = '<uuid>';
//   update chargers set mock_error_code = null            where id = '<uuid>';
//
// Auth: the signed-in user's JWT (default verify_jwt).
//
// Request:  { "chargerId": "<uuid>", "connectorId": 1 }
// Response:
//   { "success": true, "data": {
//       "chargerId": "...", "connectorId": 1,
//       "status": "Available" | "Unavailable", "errorCode": "NoError" | "..." } }
//   { "success": false, "data": { "errorCode": "CHARGER_NOT_FOUND", "error": "..." } }
//
// errorCodes (failure): INVALID_REQUEST, UNAUTHORIZED, CHARGER_NOT_FOUND,
//   INTERNAL_ERROR
//
// Deploy: supabase functions deploy ocpp-status --use-api

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, getUserId } from "../_shared/supabase.ts";
import { CONNECTOR_ID } from "../_shared/charger_sim.ts";

Deno.serve(async (req: Request) => {
  const early = preflight(req);
  if (early) return early;

  const admin = adminClient();
  const userId = await getUserId(req, admin);
  if (!userId) return fail("UNAUTHORIZED", "Please sign in.");

  const { chargerId, connectorId } = await readJson<{
    chargerId: string;
    connectorId: number;
  }>(req);
  if (typeof chargerId !== "string" || chargerId.length === 0) {
    return fail("INVALID_REQUEST", "chargerId is required.");
  }

  const { data: charger, error } = await admin
    .from("chargers")
    .select("id, mock_error_code")
    .eq("id", chargerId)
    .maybeSingle();
  if (error) {
    console.error("charger lookup failed", error);
    return fail("INTERNAL_ERROR", "Database error.");
  }
  if (!charger) {
    return fail("CHARGER_NOT_FOUND", "Charger not found.");
  }

  // Mock charger: one switch decides the reported status.
  const errorCode = (charger.mock_error_code ?? "").trim();

  return ok({
    chargerId: charger.id,
    connectorId: Number.isInteger(connectorId) ? connectorId : CONNECTOR_ID,
    status: errorCode ? "Unavailable" : "Available",
    errorCode: errorCode || "NoError",
  });
});
