// Shared Supabase helpers: a service-role client and request authentication.

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
export const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/** Service-role client: bypasses RLS. Only use after authorizing the caller. */
export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

/**
 * Returns the signed-in user's id for app-facing functions, or null when the
 * request has no valid user JWT.
 */
export async function getUserId(
  req: Request,
  admin: SupabaseClient,
): Promise<string | null> {
  const token = bearerToken(req);
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user.id;
}

/** Decodes a JWT's payload without verifying it (the gateway verifies). */
function jwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    return JSON.parse(atob(padded));
  } catch {
    return null;
  }
}

/**
 * True when the request carries a service-role credential. Used to lock the
 * charger-side functions (mock-charger, ocpp-meter-values) to pg_cron / other
 * edge functions, so the app can't inject meter readings.
 *
 * These functions are deployed WITH verify_jwt, so the Supabase gateway has
 * already checked the JWT signature before this runs; here we only check the
 * token's role claim. This works whatever format SUPABASE_SERVICE_ROLE_KEY
 * takes inside the runtime. An exact match with that env key is also
 * accepted.
 */
export function isServiceRequest(req: Request): boolean {
  const token = bearerToken(req);
  if (!token) return false;
  if (SERVICE_ROLE_KEY.length > 0 && token === SERVICE_ROLE_KEY) return true;
  return jwtPayload(token)?.role === "service_role";
}

/** The caller's Authorization header, to forward on internal calls. */
export function authorizationHeader(req: Request): string {
  return req.headers.get("Authorization") ?? "";
}

/** Result shape of the charging SQL functions. */
export type RpcResult = { ok: boolean; error_code?: string; error?: string } &
  Record<string, unknown>;

/** Calls a charging SQL function and normalizes transport errors. */
export async function callRpc(
  admin: SupabaseClient,
  fn: string,
  args: Record<string, unknown>,
): Promise<RpcResult> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) {
    console.error(`${fn} failed`, error);
    return { ok: false, error_code: "INTERNAL_ERROR", error: "Database error." };
  }
  return data as RpcResult;
}
