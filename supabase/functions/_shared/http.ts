import { SafeError } from "./errors.ts";
import { redact } from "./redaction.ts";

const REQUEST_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function requestIdFromHeaders(headers: Headers): string {
  const candidate = headers.get("x-request-id")?.trim();
  return candidate && REQUEST_ID_PATTERN.test(candidate)
    ? candidate
    : crypto.randomUUID();
}

export function successEnvelope(
  data: Record<string, unknown>,
  requestId: string,
  init: ResponseInit = {},
): Response {
  return Response.json({
    success: true,
    code: "ok",
    message: "Request completed.",
    data,
    request_id: requestId,
  }, init);
}

export function errorEnvelope(
  error: unknown,
  requestId: string,
  init: ResponseInit = {},
): Response {
  const safe = error instanceof SafeError
    ? error
    : new SafeError(500, "internal_error", "Request could not be completed.");
  return Response.json({
    success: false,
    code: safe.code,
    message: redact(safe.message),
    data: {},
    request_id: requestId,
  }, { ...init, status: safe.status });
}

export async function readJsonObject(
  req: Request,
): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new SafeError(400, "bad_request", "Request body must be valid JSON.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new SafeError(
      400,
      "bad_request",
      "Request body must be a JSON object.",
    );
  }
  return body as Record<string, unknown>;
}
