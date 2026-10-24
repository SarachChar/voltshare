// mock-charger
//
// Plays every physical charger that currently has a session charging. Called
// by pg_cron every 30s (supabase/sql/functions/trigger_mock_charger.sql).
// For each charging session, independently:
//   1. take that session's latest reading
//   2. advance it to "now" with the session's own charger power (charger_sim)
//   3. battery full        -> stop the session (battery_full)
//      booking end reached -> stop the session at end_time (time_up)
//      otherwise           -> POST an OCPP MeterValues message to
//                             ocpp-meter-values, like a real charger would
// Sessions are processed in parallel with Promise.allSettled, so one failing
// session never blocks the others.
//
// Duplicate ticks: a session whose latest reading is younger than
// MIN_INTERVAL_MS is skipped (protects against overlapping cron runs / manual
// calls). Send { "force": true } to bypass while testing.
//
// Auth: service-role JWT only. Deployed WITH verify_jwt (gateway checks the
// signature); the code then checks the token's role is service_role.
//
// Manual tick (testing):
//   curl -X POST "https://<project-ref>.supabase.co/functions/v1/mock-charger" \
//     -H "Authorization: Bearer <service_role_key>" \
//     -H "Content-Type: application/json" -d '{"force":true}'
//
// Deploy: supabase functions deploy mock-charger

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { fail, ok, preflight, readJson } from "../_shared/http.ts";
import {
  adminClient,
  authorizationHeader,
  isServiceRequest,
  SUPABASE_URL,
} from "../_shared/supabase.ts";
import { nextReading } from "../_shared/charger_sim.ts";
import {
  ActiveSession,
  buildMeterValues,
  lastReading,
  loadActiveSessions,
  stopSession,
} from "../_shared/ocpp.ts";

const MIN_INTERVAL_MS = 20_000;

type TickOutcome =
  | { sessionId: string; action: "skipped"; reason: string }
  | { sessionId: string; action: "meter_values"; soc: number; energyKwh: number }
  | { sessionId: string; action: "stopped"; reason: string };

async function tick(
  admin: ReturnType<typeof adminClient>,
  session: ActiveSession,
  force: boolean,
  auth: string,
): Promise<TickOutcome> {
  const last = lastReading(session);
  if (!last) {
    return { sessionId: session.session_id, action: "skipped", reason: "no_reading" };
  }

  const now = new Date();
  if (!force && now.getTime() - last.at.getTime() < MIN_INTERVAL_MS) {
    return { sessionId: session.session_id, action: "skipped", reason: "too_soon" };
  }

  const ratedPowerKw = Number(session.rated_power_kw);
  const endTime = new Date(session.end_time);

  // Booking over: report energy only up to end_time, then stop.
  if (now >= endTime) {
    const at = endTime > last.at ? endTime : last.at;
    const final = nextReading(last, ratedPowerKw, at);
    const result = await stopSession(
      admin, session.reservation_id, null, "time_up", final,
    );
    if (!result.ok) throw new Error(`stop failed: ${result.error_code}`);
    return { sessionId: session.session_id, action: "stopped", reason: "time_up" };
  }

  const reading = nextReading(last, ratedPowerKw, now);

  if (reading.socPercent >= 100) {
    const result = await stopSession(
      admin, session.reservation_id, null, "battery_full", reading,
    );
    if (!result.ok) throw new Error(`stop failed: ${result.error_code}`);
    return { sessionId: session.session_id, action: "stopped", reason: "battery_full" };
  }

  // Report like a real charger: OCPP MeterValues over HTTP to the CSMS.
  const response = await fetch(`${SUPABASE_URL}/functions/v1/ocpp-meter-values`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Forward the scheduler's (already verified) service-role JWT.
      Authorization: auth,
    },
    body: JSON.stringify(buildMeterValues(session, reading)),
  });
  if (!response.ok) {
    throw new Error(`ocpp-meter-values ${response.status}: ${await response.text()}`);
  }

  return {
    sessionId: session.session_id,
    action: "meter_values",
    soc: reading.socPercent,
    energyKwh: reading.energyKwh,
  };
}

Deno.serve(async (req: Request) => {
  const early = preflight(req);
  if (early) return early;

  if (!isServiceRequest(req)) {
    return fail("FORBIDDEN", "Scheduler only.");
  }

  const { force } = await readJson<{ force: boolean }>(req);
  const admin = adminClient();

  let sessions: ActiveSession[];
  try {
    sessions = await loadActiveSessions(admin);
  } catch (error) {
    console.error("loadActiveSessions failed", error);
    return fail("INTERNAL_ERROR", "Couldn't load charging sessions.");
  }

  const settled = await Promise.allSettled(
    sessions.map((s) => tick(admin, s, force === true, authorizationHeader(req))),
  );

  const results = settled.map((r, i) => {
    if (r.status === "fulfilled") return r.value;
    console.error(`tick failed for session ${sessions[i].session_id}`, r.reason);
    return {
      sessionId: sessions[i].session_id,
      action: "error",
      error: String(r.reason),
    };
  });

  return ok({ sessions: sessions.length, results });
});
