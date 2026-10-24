// ocpp-remote-start
//
// App -> CSMS: "start charging for this reservation". In real OCPP the CSMS
// would send RemoteStartTransaction to the charger and wait for it to accept
// and send StartTransaction. Here the charger is mocked: it always accepts,
// and its first reading (meterStart, SoC, power) comes from _shared/charger_sim.
// All business rules are enforced in SQL (ocpp_start_session).
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Request:  { "reservationId": "<uuid>" }
// Response:
//   { "success": true, "data": {
//       "status": "Charging", "sessionId": "...", "chargerId": "...",
//       "connectorId": 1, "transactionId": 12345, "meterStart": 1234567,
//       "startedAt": "2026-10-18T20:15:00Z" } }
//   { "success": false, "data": { "errorCode": "TOO_EARLY", "error": "..." } }
//
// errorCodes: INVALID_REQUEST, UNAUTHORIZED, RESERVATION_NOT_FOUND, NOT_OWNER,
//   SESSION_ALREADY_STARTED, RESERVATION_CANCELLED, RESERVATION_NOT_ACTIVE,
//   TOO_EARLY, RESERVATION_EXPIRED, CHARGER_IN_USE, INTERNAL_ERROR
//
// Deploy: supabase functions deploy ocpp-remote-start

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, callRpc, getUserId } from "../_shared/supabase.ts";
import {
  CONNECTOR_ID,
  randomMeterStartWh,
  startReading,
} from "../_shared/charger_sim.ts";

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

  // The charger's rated power seeds the first reading. If the reservation
  // doesn't exist we still fall through so SQL returns the proper error code.
  const { data: res } = await admin
    .from("reservations")
    .select("chargers(power_kw)")
    .eq("id", reservationId)
    .maybeSingle();
  const charger = (res as { chargers?: { power_kw?: number } } | null)
    ?.chargers;
  const ratedPowerKw = Number(charger?.power_kw ?? 7);

  // Mock charger: accepts and reports its initial state.
  const first = startReading(ratedPowerKw);

  const result = await callRpc(admin, "ocpp_start_session", {
    p_reservation_id: reservationId,
    p_user_id: userId,
    p_meter_start_wh: randomMeterStartWh(),
    p_start_soc: first.socPercent,
    p_power_kw: first.powerKw,
  });

  if (!result.ok) {
    return fail(result.error_code ?? "INTERNAL_ERROR", result.error ?? "Rejected.");
  }

  return ok({
    status: "Charging",
    sessionId: result.session_id,
    chargerId: result.charger_id,
    connectorId: CONNECTOR_ID,
    transactionId: result.transaction_id,
    meterStart: result.meter_start,
    startedAt: result.started_at,
  });
});
