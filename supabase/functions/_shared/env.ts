import { validationFailed } from "./errors.ts";

export interface JsonWebKeySet {
  keys: JsonWebKey[];
}

export interface AppEnv {
  supabaseUrl: string;
  publishableKey: string;
  serviceRoleKey: string;
  jwksUrl: string;
  appBaseUrl: string;
  appOrigin: string;
  jwks?: JsonWebKeySet;
}

function requireEnvValue(
  source: Record<string, string | undefined>,
  name: string,
): string {
  const value = source[name]?.trim();
  if (!value) {
    throw validationFailed(`Required environment variable ${name} is missing.`);
  }
  return value;
}

function validateAppBaseUrl(raw: string): URL {
  return validateHttpsOrLocalUrl(raw, "APP_BASE_URL");
}

function validateSupabaseUrl(raw: string): URL {
  return validateHttpsOrLocalUrl(raw, "SUPABASE_URL");
}

function validateHttpsOrLocalUrl(raw: string, name: string): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw validationFailed(`${name} must be an absolute URL.`);
  }
  const localHttp = url.protocol === "http:" &&
    (
      url.hostname === "localhost" ||
      url.hostname === "127.0.0.1" ||
      url.hostname === "host.docker.internal" ||
      url.hostname === "kong"
    );
  if (url.protocol !== "https:" && !localHttp) {
    throw validationFailed(
      `${name} must use HTTPS outside local development.`,
    );
  }
  url.hash = "";
  return url;
}

function jwksUrlForSupabase(supabaseUrl: URL): string {
  return new URL("/auth/v1/.well-known/jwks.json", supabaseUrl).toString();
}

export function loadAppEnv(
  source: Record<string, string | undefined> = Deno.env.toObject(),
): AppEnv {
  const publishableKey = source.SUPABASE_PUBLISHABLE_KEY?.trim() ||
    source.SUPABASE_ANON_KEY?.trim() ||
    source.SUPABASE_PUBLISHABLE_KEYS?.trim();
  if (!publishableKey) {
    throw validationFailed(
      "Required environment variable SUPABASE_PUBLISHABLE_KEY is missing.",
    );
  }
  const supabase = validateSupabaseUrl(requireEnvValue(source, "SUPABASE_URL"));
  const appBase = validateAppBaseUrl(requireEnvValue(source, "APP_BASE_URL"));
  return {
    supabaseUrl: supabase.toString().replace(/\/$/, ""),
    publishableKey,
    serviceRoleKey: requireEnvValue(source, "SUPABASE_SERVICE_ROLE_KEY"),
    jwksUrl: jwksUrlForSupabase(supabase),
    appBaseUrl: appBase.toString().replace(/\/$/, ""),
    appOrigin: appBase.origin,
  };
}
