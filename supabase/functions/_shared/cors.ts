import { forbidden } from "./errors.ts";

export const allowedMethods = "POST, OPTIONS";
export const allowedHeaders =
  "authorization, x-client-info, apikey, content-type, x-request-id";

export function corsHeaders(appOrigin: string): Headers {
  return new Headers({
    "Access-Control-Allow-Origin": appOrigin,
    "Access-Control-Allow-Methods": allowedMethods,
    "Access-Control-Allow-Headers": allowedHeaders,
    "Vary": "Origin",
  });
}

export function requireAllowedOrigin(req: Request, appOrigin: string): string {
  const origin = req.headers.get("Origin");
  if (origin !== appOrigin) {
    throw forbidden("Origin is not allowed.");
  }
  return origin;
}

export function optionsResponse(req: Request, appOrigin: string): Response {
  requireAllowedOrigin(req, appOrigin);
  return new Response(null, { status: 204, headers: corsHeaders(appOrigin) });
}
