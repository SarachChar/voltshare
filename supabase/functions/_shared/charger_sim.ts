// The mock charger's physics. Everything a real charger would measure and
// report is produced here, so swapping in real hardware later means deleting
// this file (and mock-charger), not touching the backend.
//
// Model:
//   - Vehicle battery: BATTERY_CAPACITY_KWH, starting SoC random 10-40%.
//   - Power: the charger's rated power +/- 2% noise; above 80% SoC it tapers
//     linearly down to 20% of rated at 100% (like real CC/CV charging).
//   - Energy over a step: power * dt.  SoC gain: energy / capacity.

export const BATTERY_CAPACITY_KWH = 60;

/** OCPP connector used for every charger (the schema has no connectors yet). */
export const CONNECTOR_ID = 1;

export type Reading = {
  socPercent: number;
  powerKw: number;
  /** Energy delivered in this session so far (kWh). */
  energyKwh: number;
  at: Date;
};

const round = (value: number, digits: number) => {
  const f = 10 ** digits;
  return Math.round(value * f) / f;
};

/** Power the charger delivers at a given SoC. */
export function chargingPowerKw(ratedPowerKw: number, socPercent: number): number {
  if (socPercent >= 100) return 0;
  const taper = socPercent <= 80
    ? 1
    : Math.max(0.2, 1 - ((socPercent - 80) / 20) * 0.8);
  const noise = 1 + (Math.random() * 0.04 - 0.02);
  return ratedPowerKw * taper * noise;
}

/** What the charger reports when a transaction starts. */
export function startReading(ratedPowerKw: number, at = new Date()): Reading {
  const socPercent = 10 + Math.floor(Math.random() * 31); // 10..40
  return {
    socPercent,
    powerKw: round(chargingPowerKw(ratedPowerKw, socPercent), 3),
    energyKwh: 0,
    at,
  };
}

/**
 * The charger's energy register at transaction start (Wh). Real meters are
 * cumulative over the charger's lifetime, so start somewhere non-zero.
 */
export function randomMeterStartWh(): number {
  return 100_000 + Math.floor(Math.random() * 1_900_000);
}

/** Advances [last] to [at] at the charger's [ratedPowerKw]. */
export function nextReading(
  last: Reading,
  ratedPowerKw: number,
  at = new Date(),
): Reading {
  const dtHours = Math.max(0, at.getTime() - last.at.getTime()) / 3_600_000;
  const power = chargingPowerKw(ratedPowerKw, last.socPercent);
  const deltaKwh = power * dtHours;
  const socPercent = Math.min(
    100,
    last.socPercent + (deltaKwh / BATTERY_CAPACITY_KWH) * 100,
  );
  return {
    socPercent: round(socPercent, 2),
    powerKw: socPercent >= 100 ? 0 : round(power, 3),
    energyKwh: round(last.energyKwh + deltaKwh, 3),
    at,
  };
}
