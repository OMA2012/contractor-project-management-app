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
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw validationFailed("APP_BASE_URL must be an absolute URL.");
  }
  const localHttp = url.protocol === "http:" &&
    (url.hostname === "localhost" || url.hostname === "127.0.0.1");
  if (url.protocol !== "https:" && !localHttp) {
    throw validationFailed(
      "APP_BASE_URL must use HTTPS outside local development.",
    );
  }
  url.hash = "";
  return url;
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
  const appBase = validateAppBaseUrl(requireEnvValue(source, "APP_BASE_URL"));
  return {
    supabaseUrl: requireEnvValue(source, "SUPABASE_URL"),
    publishableKey,
    serviceRoleKey: requireEnvValue(source, "SUPABASE_SERVICE_ROLE_KEY"),
    jwksUrl: requireEnvValue(source, "SUPABASE_JWKS_URL"),
    appBaseUrl: appBase.toString().replace(/\/$/, ""),
    appOrigin: appBase.origin,
  };
}
