// ocpp-remote-stop
//
// App -> CSMS: "stop charging for this reservation". In real OCPP the CSMS
// sends RemoteStopTransaction and the charger answers with StopTransaction
// (incl. meterStop). Here the mock charger's final reading is computed from
// its last reading up to now (_shared/charger_sim), then ocpp_stop_session
// closes the session, completes the reservation and creates the bill.
//
// Auth: the signed-in driver's JWT (default verify_jwt).
//
// Request:  { "reservationId": "<uuid>" }
// Response:
//   { "success": true, "data": {
//       "status": "Completed", "sessionId": "...", "chargerId": "...",
//       "connectorId": 1, "transactionId": 12345, "meterStop": 1240000,
//       "stoppedAt": "2026-10-18T21:00:00Z", "stopReason": "user",
//       "totalEnergyKwh": 12.48, "paymentStatus": "unpaid", "totalAmount": 79.84 } }
//   { "success": false, "data": { "errorCode": "NO_ACTIVE_TRANSACTION", "error": "..." } }
//
// errorCodes: INVALID_REQUEST, UNAUTHORIZED, RESERVATION_NOT_FOUND, NOT_OWNER,
//   NO_ACTIVE_TRANSACTION, INTERNAL_ERROR
//
// Deploy: supabase functions deploy ocpp-remote-stop

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, getUserId } from "../_shared/supabase.ts";
import { nextReading, Reading } from "../_shared/charger_sim.ts";
import {
  lastReading,
  loadActiveSessions,
  stopResponseData,
  stopSession,
} from "../_shared/ocpp.ts";

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

  // Final reading from the (mock) charger. If the session isn't active the
  // reading stays null and SQL returns the proper error code.
  let finalReading: Reading | null = null;
  try {
    const sessions = await loadActiveSessions(admin);
    const session = sessions.find((s) => s.reservation_id === reservationId);
    const last = session ? lastReading(session) : null;
    if (session && last) {
      // Energy only counts up to the end of the booking, even if the
      // auto-stop tick hasn't run yet.
      const now = new Date();
      const endTime = new Date(session.end_time);
      let at = now < endTime ? now : endTime;
      if (at < last.at) at = last.at;
      finalReading = nextReading(last, Number(session.rated_power_kw), at);
    }
  } catch (error) {
    console.error("loadActiveSessions failed", error);
    return fail("INTERNAL_ERROR", "Couldn't read the charging session.");
  }

  const result = await stopSession(
    admin,
    reservationId,
    userId,
    "user",
    finalReading,
  );

  if (!result.ok) {
    return fail(result.error_code ?? "INTERNAL_ERROR", result.error ?? "Rejected.");
  }

  return ok(stopResponseData(result));
});
