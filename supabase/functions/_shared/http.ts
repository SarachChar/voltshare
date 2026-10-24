// Shared HTTP helpers for the charging / OCPP edge functions.
//
// Every response uses the app-facing envelope:
//   success -> { "success": true,  "data": { ... } }
//   failure -> { "success": false, "data": { "errorCode": "...", "error": "..." } }

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function ok(data: Record<string, unknown>, status = 200): Response {
  return json({ success: true, data }, status);
}

export function fail(errorCode: string, error: string, status?: number): Response {
  return json(
    { success: false, data: { errorCode, error } },
    status ?? statusForError(errorCode),
  );
}

/** HTTP status for each errorCode returned by the SQL functions / handlers. */
export function statusForError(errorCode: string): number {
  switch (errorCode) {
    case "INVALID_REQUEST":
      return 400;
    case "UNAUTHORIZED":
      return 401;
    case "PAYMENT_DECLINED":
      return 402;
    case "NOT_OWNER":
    case "FORBIDDEN":
      return 403;
    case "RESERVATION_NOT_FOUND":
    case "SESSION_NOT_FOUND":
    case "NO_ACTIVE_TRANSACTION":
    case "INVALID_PAYMENT_METHOD":
      return 404;
    case "METHOD_NOT_ALLOWED":
      return 405;
    case "INTERNAL_ERROR":
      return 500;
    default:
      // Business-rule rejections: TOO_EARLY, CHARGER_IN_USE, ALREADY_PAID, ...
      return 409;
  }
}

/** Handles CORS preflight and non-POST methods. Returns null to continue. */
export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return fail("METHOD_NOT_ALLOWED", "Use POST.");
  }
  return null;
}

/** Parses the JSON body, or returns {} when the body is empty / invalid. */
export async function readJson<T = Record<string, unknown>>(
  req: Request,
): Promise<Partial<T>> {
  try {
    const body = await req.json();
    return body && typeof body === "object" ? body : {};
  } catch {
    return {};
  }
}
