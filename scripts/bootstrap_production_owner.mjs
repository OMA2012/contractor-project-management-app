import { createClient } from "@supabase/supabase-js";

export const EXIT = Object.freeze({
  ok: 0,
  validation: 1,
  authPreparation: 2,
  recoveryNotProven: 3,
  deliveryUnconfirmed: 4,
  expiredInvitation: 5,
  internal: 6,
});

const CONFIRMATION = "CREATE FIRST CONTRACTOR OWNER";
const TOKEN_BYTES = 32;

function safeError(message, exitCode) {
  return Object.assign(new Error(message), { exitCode });
}

export function maskEmail(email) {
  const [local, domain] = email.split("@");
  const visible = local.slice(0, 2);
  return `${visible}${"*".repeat(Math.max(local.length - 2, 1))}@${domain}`;
}

export function normalizeEmail(value) {
  if (typeof value !== "string") {
    throw safeError("BOOTSTRAP_OWNER_EMAIL is invalid.", EXIT.validation);
  }
  const email = value.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw safeError("BOOTSTRAP_OWNER_EMAIL is invalid.", EXIT.validation);
  }
  return email;
}

export function validateBaseUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw safeError("APP_BASE_URL must be an absolute URL.", EXIT.validation);
  }
  const localHttp = url.protocol === "http:" &&
    (url.hostname === "localhost" || url.hostname === "127.0.0.1");
  if (url.protocol !== "https:" && !localHttp) {
    throw safeError(
      "APP_BASE_URL must use HTTPS outside local development.",
      EXIT.validation,
    );
  }
  url.hash = "";
  url.search = "";
  return url.toString().replace(/\/$/, "");
}

export function activationRedirect(appBaseUrl) {
  const url = new URL(appBaseUrl);
  url.pathname = "/owner/activate";
  url.search = "";
  url.hash = "";
  return url.toString();
}

export function loadConfig(env = Deno.env.toObject()) {
  for (
    const name of [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "APP_BASE_URL",
      "BOOTSTRAP_OWNER_EMAIL",
      "BOOTSTRAP_OWNER_FULL_NAME",
      "BOOTSTRAP_CONFIRMATION",
    ]
  ) {
    if (!env[name]?.trim()) {
      throw safeError(
        `Required environment variable ${name} is missing.`,
        EXIT.validation,
      );
    }
  }
  if (env.BOOTSTRAP_CONFIRMATION !== CONFIRMATION) {
    throw safeError(
      "BOOTSTRAP_CONFIRMATION does not match the required phrase.",
      EXIT.validation,
    );
  }
  const fullName = env.BOOTSTRAP_OWNER_FULL_NAME.trim();
  if (!fullName) {
    throw safeError("BOOTSTRAP_OWNER_FULL_NAME is required.", EXIT.validation);
  }
  const appBaseUrl = validateBaseUrl(env.APP_BASE_URL.trim());
  return {
    supabaseUrl: env.SUPABASE_URL.trim(),
    serviceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY.trim(),
    appBaseUrl,
    redirectTo: activationRedirect(appBaseUrl),
    email: normalizeEmail(env.BOOTSTRAP_OWNER_EMAIL),
    fullName,
  };
}

export function generateTokenBytes(
  random = crypto.getRandomValues.bind(crypto),
) {
  const bytes = new Uint8Array(TOKEN_BYTES);
  random(bytes);
  return bytes;
}

export async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

export function byteaHex(bytes) {
  return `\\x${
    Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("")
  }`;
}

export function safeAuthUserId(data) {
  const id = data?.user?.id;
  if (typeof id !== "string" || !id) {
    throw Object.assign(new Error("Auth invitation response was invalid."), {
      exitCode: EXIT.authPreparation,
    });
  }
  return id;
}

function firstRow(data) {
  if (
    Array.isArray(data) && data.length > 0 && data[0] &&
    typeof data[0] === "object"
  ) return data[0];
  if (data && typeof data === "object" && !Array.isArray(data)) return data;
  return null;
}

function isExpectedBootstrapRejection(error) {
  return error?.code === "42501" || error?.code === "23505" ||
    error?.code === "23514";
}

function isExpiredRecovery(error) {
  return error?.code === "P0001" || /expired/i.test(error?.message ?? "");
}

export async function bootstrapProductionOwner({
  env = Deno.env.toObject(),
  clientFactory = createClient,
  random,
  output = console.log,
} = {}) {
  try {
    const config = loadConfig(env);
    const requestId = crypto.randomUUID();
    const correlationId = crypto.randomUUID();
    const client = clientFactory(config.supabaseUrl, config.serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const tokenDigest = byteaHex(await sha256(generateTokenBytes(random)));
    const linkResult = await client.auth.admin.generateLink({
      type: "invite",
      email: config.email,
      options: { redirectTo: config.redirectTo },
    });
    if (linkResult.error) {
      return safeResult(
        EXIT.authPreparation,
        "Auth invitation preparation failed.",
        config.email,
      );
    }
    const authUserId = safeAuthUserId(linkResult.data);

    let proven = false;
    let bootstrapRow = null;
    const bootstrapResult = await client.rpc("server_bootstrap_first_owner", {
      p_owner_auth_subject: authUserId,
      p_normalized_email: config.email,
      p_owner_full_name: config.fullName,
      p_token_hash: tokenDigest,
      p_request_identifier: requestId,
      p_correlation_identifier: correlationId,
    });

    if (!bootstrapResult.error) {
      bootstrapRow = firstRow(bootstrapResult.data);
      proven = true;
    } else if (isExpectedBootstrapRejection(bootstrapResult.error)) {
      const recovery = await client.rpc("server_first_owner_delivery_context", {
        p_owner_auth_subject: authUserId,
        p_normalized_email: config.email,
      });
      if (isExpiredRecovery(recovery.error)) {
        return safeResult(
          EXIT.expiredInvitation,
          "Invitation is expired; a separate approved recovery operation is required.",
          config.email,
          authUserId,
        );
      }
      if (recovery.error) {
        return safeResult(
          EXIT.recoveryNotProven,
          "First Owner recovery was not proven.",
          config.email,
          authUserId,
        );
      }
      bootstrapRow = firstRow(recovery.data);
      proven = bootstrapRow?.auth_subject === authUserId &&
        bootstrapRow?.normalized_email === config.email &&
        bootstrapRow?.account_status === "INVITED" &&
        bootstrapRow?.is_active === false &&
        bootstrapRow?.invitation_status === "PENDING";
      if (!proven) {
        return safeResult(
          EXIT.recoveryNotProven,
          "First Owner recovery was not proven.",
          config.email,
          authUserId,
        );
      }
    } else {
      return safeResult(
        EXIT.recoveryNotProven,
        "Database bootstrap was rejected.",
        config.email,
        authUserId,
      );
    }

    const delivery = await client.auth.admin.inviteUserByEmail(config.email, {
      redirectTo: config.redirectTo,
    });
    if (delivery.error) {
      return safeResult(
        EXIT.deliveryUnconfirmed,
        "Invitation delivery was not confirmed. Rerun the guarded command to retry after same-identity recovery.",
        config.email,
        authUserId,
        bootstrapRow,
      );
    }
    return safeResult(
      EXIT.ok,
      "First Owner bootstrap invitation delivered.",
      config.email,
      authUserId,
      bootstrapRow,
    );
  } catch (error) {
    const exitCode = Number.isInteger(error?.exitCode)
      ? error.exitCode
      : EXIT.internal;
    const message =
      exitCode === EXIT.validation || exitCode === EXIT.authPreparation
        ? error?.message ?? "Bootstrap failed."
        : "Unexpected bootstrap failure.";
    return safeResult(exitCode, message, undefined);
  } finally {
    void output;
  }
}

function safeResult(exitCode, message, email, authUserId, row) {
  return {
    exitCode,
    lines: [
      `status=${exitCode === 0 ? "ok" : "failed"}`,
      `exit_code=${exitCode}`,
      `message=${message}`,
      ...(email ? [`owner_email=${maskEmail(email)}`] : []),
      ...(authUserId ? [`auth_user_id=${authUserId}`] : []),
      ...(row?.owner_user_id ? [`owner_user_id=${row.owner_user_id}`] : []),
      ...(row?.invitation_id ? [`invitation_id=${row.invitation_id}`] : []),
      ...(row?.expires_at ? [`expires_at=${row.expires_at}`] : []),
    ],
  };
}

export async function main() {
  const result = await bootstrapProductionOwner();
  for (const line of result.lines) console.log(line);
  Deno.exit(result.exitCode);
}

if (import.meta.main) {
  await main();
}
