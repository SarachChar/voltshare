// OCPP-flavoured helpers shared by the charging edge functions: loading the
// live state of a session, building / parsing MeterValues, and stopping a
// session (used by both ocpp-remote-stop and the mock charger's auto-stop).

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { callRpc, RpcResult } from "./supabase.ts";
import { CONNECTOR_ID, Reading } from "./charger_sim.ts";

/** Row returned by mock_charger_active_sessions(). */
export type ActiveSession = {
  session_id: string;
  reservation_id: string;
  transaction_id: number;
  charger_id: string;
  meter_start_wh: number;
  rated_power_kw: number;
  end_time: string;
  last_soc: number | null;
  last_power_kw: number | null;
  last_energy_kwh: number | null;
  last_reading_at: string | null;
};

export async function loadActiveSessions(
  admin: SupabaseClient,
): Promise<ActiveSession[]> {
  const { data, error } = await admin.rpc("mock_charger_active_sessions");
  if (error) throw error;
  return (data ?? []) as ActiveSession[];
}

/** The latest reading of an active session, or null if it has none. */
export function lastReading(s: ActiveSession): Reading | null {
  if (s.last_reading_at == null) return null;
  return {
    socPercent: Number(s.last_soc ?? 0),
    powerKw: Number(s.last_power_kw ?? 0),
    energyKwh: Number(s.last_energy_kwh ?? 0),
    at: new Date(s.last_reading_at),
  };
}

// --- MeterValues --------------------------------------------------------------

export type SampledValue = {
  value: string;
  context: string;
  format: string;
  measurand: string;
  unit: string;
};

export type MeterValuesRequest = {
  chargerId: string;
  connectorId: number;
  transactionId: number;
  meterValue: { timestamp: string; sampledValue: SampledValue[] }[];
};

const sample = (value: string, measurand: string, unit: string): SampledValue => ({
  value,
  context: "Sample.Periodic",
  format: "Raw",
  measurand,
  unit,
});

/** Builds the OCPP MeterValues message a charger would send for [reading]. */
export function buildMeterValues(
  s: ActiveSession,
  reading: Reading,
): MeterValuesRequest {
  const registerWh = Number(s.meter_start_wh) + reading.energyKwh * 1000;
  return {
    chargerId: s.charger_id,
    connectorId: CONNECTOR_ID,
    transactionId: Number(s.transaction_id),
    meterValue: [
      {
        timestamp: reading.at.toISOString(),
        sampledValue: [
          sample(registerWh.toFixed(0), "Energy.Active.Import.Register", "Wh"),
          sample(reading.powerKw.toFixed(3), "Power.Active.Import", "kW"),
          sample(reading.socPercent.toFixed(2), "SoC", "Percent"),
        ],
      },
    ],
  };
}

/** Pulls the measurands we store out of a MeterValues sample. */
export function parseSample(entry: {
  timestamp?: string;
  sampledValue?: SampledValue[];
}): { registerWh: number; powerKw: number; soc: number; timestamp: string } | null {
  const values = entry.sampledValue ?? [];
  const find = (measurand: string) =>
    values.find((v) => v.measurand === measurand);

  const energy = find("Energy.Active.Import.Register");
  const power = find("Power.Active.Import");
  const soc = find("SoC");
  if (!energy || !power || !soc) return null;

  // Normalize units: register to Wh, power to kW.
  const energyValue = Number(energy.value);
  const registerWh = energy.unit === "kWh" ? energyValue * 1000 : energyValue;
  const powerValue = Number(power.value);
  const powerKw = power.unit === "W" ? powerValue / 1000 : powerValue;
  const socValue = Number(soc.value);

  if (![registerWh, powerKw, socValue].every(Number.isFinite)) return null;

  return {
    registerWh,
    powerKw,
    soc: socValue,
    timestamp: entry.timestamp ?? new Date().toISOString(),
  };
}

// --- Stop -----------------------------------------------------------------------

export type StopReason = "user" | "time_up" | "battery_full";

/**
 * Stops the session for [reservationId] with the charger's [finalReading].
 * [userId] null = system stop (no ownership check).
 */
export function stopSession(
  admin: SupabaseClient,
  reservationId: string,
  userId: string | null,
  reason: StopReason,
  finalReading: Reading | null,
): Promise<RpcResult> {
  return callRpc(admin, "ocpp_stop_session", {
    p_reservation_id: reservationId,
    p_user_id: userId,
    p_stop_reason: reason,
    p_final_soc: finalReading?.socPercent ?? 0,
    p_final_power_kw: 0,
    p_final_energy_kwh: finalReading?.energyKwh ?? 0,
  });
}

/** Maps a successful ocpp_stop_session result to the app-facing data. */
export function stopResponseData(result: RpcResult): Record<string, unknown> {
  return {
    status: "Completed",
    sessionId: result.session_id,
    chargerId: result.charger_id,
    connectorId: CONNECTOR_ID,
    transactionId: result.transaction_id,
    meterStop: result.meter_stop,
    stoppedAt: result.stopped_at,
    stopReason: result.stop_reason,
    totalEnergyKwh: result.total_energy_kwh,
    paymentStatus: result.payment_status,
    totalAmount: result.total_amount,
  };
}
