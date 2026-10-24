// ocpp-meter-values
//
// Charger -> CSMS: the OCPP MeterValues message. This is the ingest endpoint a
// real charger (via an OCPP gateway) would post to; today the only caller is
// the mock-charger function. Each sample is stored in session_streams, which
// the app receives through Realtime.
//
// Auth: service-role JWT only (Authorization: Bearer <service_role_key>), so
// the app can't inject readings. Deployed WITH verify_jwt (gateway checks the
// signature); the code then checks the token's role is service_role.
//
// Request (OCPP 1.6 MeterValues.req, JSON):
//   {
//     "chargerId": "<uuid>", "connectorId": 1, "transactionId": 12345,
//     "meterValue": [{
//       "timestamp": "2026-10-18T14:10:00Z",
//       "sampledValue": [
//         { "value": "1234567", "measurand": "Energy.Active.Import.Register", "unit": "Wh", ... },
//         { "value": "21.870",  "measurand": "Power.Active.Import",          "unit": "kW", ... },
//         { "value": "18.40",   "measurand": "SoC",                          "unit": "Percent", ... }
//       ]
//     }]
//   }
// Response:
//   { "success": true, "data": { "chargerId", "transactionId", "status": "Charging", "stored": 1 } }
//   { "success": false, "data": { "errorCode": "NO_ACTIVE_TRANSACTION", "error": "..." } }
//
// Deploy: supabase functions deploy ocpp-meter-values

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import { adminClient, callRpc, isServiceRequest } from "../_shared/supabase.ts";
import { MeterValuesRequest, parseSample } from "../_shared/ocpp.ts";

Deno.serve(async (req: Request) => {
  const early = preflight(req);
  if (early) return early;

  if (!isServiceRequest(req)) {
    return fail("FORBIDDEN", "Chargers only.");
  }

  const body = await readJson<MeterValuesRequest>(req);
  const transactionId = Number(body.transactionId);
  const entries = Array.isArray(body.meterValue) ? body.meterValue : [];
  if (!Number.isInteger(transactionId) || entries.length === 0) {
    return fail("INVALID_REQUEST", "transactionId and meterValue are required.");
  }

  const admin = adminClient();
  let stored = 0;

  for (const entry of entries) {
    const parsed = parseSample(entry);
    if (!parsed) {
      return fail("INVALID_REQUEST", "Missing or invalid sampledValue.");
    }

    const result = await callRpc(admin, "ocpp_record_meter_value", {
      p_transaction_id: transactionId,
      p_soc: parsed.soc,
      p_power_kw: parsed.powerKw,
      p_register_wh: parsed.registerWh,
      p_timestamp: parsed.timestamp,
    });

    if (!result.ok) {
      return fail(result.error_code ?? "INTERNAL_ERROR", result.error ?? "Rejected.");
    }
    stored++;
  }

  return ok({
    chargerId: body.chargerId,
    transactionId,
    status: "Charging",
    stored,
  });
});
