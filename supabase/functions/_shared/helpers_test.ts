import { authenticateRequest } from "./auth.ts";
import { corsHeaders, optionsResponse, requireAllowedOrigin } from "./cors.ts";
import { deniedLogArgs } from "./denied_log.ts";
import { loadAppEnv } from "./env.ts";
import { SafeError } from "./errors.ts";
import {
  errorEnvelope,
  readJsonObject,
  requestIdFromHeaders,
  successEnvelope,
} from "./http.ts";
import { invitationUrl } from "./invitation_url.ts";
import { redact } from "./redaction.ts";
import {
  byteaHex,
  decodeBase64Url,
  generateInvitationToken,
  sha256Digest,
} from "./token.ts";
import {
  fullName,
  normalizedEmail,
  reason,
  rejectUnknownFields,
  uuidValue,
} from "./validation.ts";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(
  actual: unknown,
  expected: unknown,
  message?: string,
): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function assertRejects(
  fn: () => unknown | Promise<unknown>,
  messageIncludes?: string,
): Promise<void> {
  try {
    await fn();
  } catch (error) {
    if (
      messageIncludes &&
      !(error instanceof Error && error.message.includes(messageIncludes))
    ) {
      throw new Error(`expected error including ${messageIncludes}`);
    }
    return;
  }
  throw new Error("expected rejection");
}

function assertThrows(fn: () => unknown, messageIncludes?: string): void {
  try {
    fn();
  } catch (error) {
    if (
      messageIncludes &&
      !(error instanceof Error && error.message.includes(messageIncludes))
    ) {
      throw new Error(`expected error including ${messageIncludes}`);
    }
    return;
  }
  throw new Error("expected throw");
}

function testEnv(overrides: Record<string, string | undefined> = {}) {
  return {
    SUPABASE_URL: "http://127.0.0.1:54321",
    SUPABASE_PUBLISHABLE_KEY: "publishable-placeholder",
    SUPABASE_SERVICE_ROLE_KEY: "service-placeholder",
    APP_BASE_URL: "http://localhost:3000",
    ...overrides,
  };
}

Deno.test("required environment validation keeps secret values out of errors", () => {
  const env = loadAppEnv(testEnv());
  assertEquals(env.supabaseUrl, "http://127.0.0.1:54321");
  assertEquals(
    env.jwksUrl,
    "http://127.0.0.1:54321/auth/v1/.well-known/jwks.json",
  );
  assertEquals(env.appOrigin, "http://localhost:3000");
  assertEquals(env.appBaseUrl, "http://localhost:3000");
  assertEquals(
    loadAppEnv(testEnv({ SUPABASE_URL: "http://127.0.0.1:54321/" })).jwksUrl,
    "http://127.0.0.1:54321/auth/v1/.well-known/jwks.json",
  );
  assertEquals(
    loadAppEnv(testEnv({
      SUPABASE_URL: "http://host.docker.internal:54321",
    })).jwksUrl,
    "http://host.docker.internal:54321/auth/v1/.well-known/jwks.json",
  );
  assertEquals(
    loadAppEnv(testEnv({ SUPABASE_URL: "http://kong:8000" })).jwksUrl,
    "http://kong:8000/auth/v1/.well-known/jwks.json",
  );
  const hosted = loadAppEnv(testEnv({
    SUPABASE_URL: "https://project-ref.supabase.co",
    APP_BASE_URL: "https://app.example.test",
  }));
  assertEquals(hosted.supabaseUrl, "https://project-ref.supabase.co");
  assertEquals(
    hosted.jwksUrl,
    "https://project-ref.supabase.co/auth/v1/.well-known/jwks.json",
  );
  assertThrows(
    () => loadAppEnv(testEnv({ SUPABASE_URL: "" })),
    "SUPABASE_URL",
  );
  assertThrows(
    () => loadAppEnv(testEnv({ SUPABASE_URL: "http://example.com" })),
    "SUPABASE_URL",
  );
  assertEquals(
    loadAppEnv(testEnv({
      SUPABASE_JWKS_URL: "https://request-controlled.example.test/jwks.json",
    })).jwksUrl,
    "http://127.0.0.1:54321/auth/v1/.well-known/jwks.json",
  );
  assertThrows(
    () => loadAppEnv(testEnv({ SUPABASE_SERVICE_ROLE_KEY: "" })),
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  try {
    loadAppEnv(
      testEnv({
        APP_BASE_URL: "http://example.com",
        SUPABASE_SERVICE_ROLE_KEY: "secret-value",
      }),
    );
  } catch (error) {
    assert(error instanceof Error);
    assert(!error.message.includes("secret-value"));
    return;
  }
  throw new Error("expected APP_BASE_URL rejection");
});

Deno.test("origin and CORS helpers use exact origin and no wildcard", () => {
  const headers = corsHeaders("https://app.example.test");
  assertEquals(
    headers.get("Access-Control-Allow-Origin"),
    "https://app.example.test",
  );
  assertEquals(headers.get("Access-Control-Allow-Methods"), "POST, OPTIONS");
  assertEquals(
    headers.get("Access-Control-Allow-Headers"),
    "authorization, apikey, content-type, x-request-id",
  );
  assertEquals(headers.get("Vary"), "Origin");
  assert(!Array.from(headers.values()).includes("*"));

  const allowed = new Request("https://edge.test", {
    headers: { Origin: "https://app.example.test" },
  });
  assertEquals(
    requireAllowedOrigin(allowed, "https://app.example.test"),
    "https://app.example.test",
  );
  const response = optionsResponse(allowed, "https://app.example.test");
  assertEquals(response.status, 204);
  assertEquals(
    response.headers.get("Access-Control-Allow-Origin"),
    "https://app.example.test",
  );

  assertThrows(
    () =>
      requireAllowedOrigin(
        new Request("https://edge.test"),
        "https://app.example.test",
      ),
    "Origin",
  );
  assertThrows(
    () =>
      requireAllowedOrigin(
        new Request("https://edge.test", {
          headers: { Origin: "https://evil.test" },
        }),
        "https://app.example.test",
      ),
    "Origin",
  );
});

Deno.test("request ids and envelopes are stable and sanitized", async () => {
  const generated = requestIdFromHeaders(new Headers());
  assert(uuidValue(generated));
  const supplied = "11111111-1111-4111-8111-111111111111";
  assertEquals(
    requestIdFromHeaders(new Headers({ "x-request-id": supplied })),
    supplied,
  );
  assert(
    requestIdFromHeaders(new Headers({ "x-request-id": "bad" })) !== "bad",
  );

  const ok = await successEnvelope({ done: true }, supplied).json();
  assertEquals(ok, {
    success: true,
    code: "ok",
    message: "Request completed.",
    data: { done: true },
    request_id: supplied,
  });
  const err = await errorEnvelope(
    new SafeError(400, "bad_request", "token 123456 leaked"),
    supplied,
  ).json();
  assertEquals(err.success, false);
  assertEquals(err.data, {});
  assert(!JSON.stringify(err).includes("123456"));

  const body = await readJsonObject(
    new Request("https://edge.test", {
      method: "POST",
      body: JSON.stringify({ a: 1 }),
    }),
  );
  assertEquals(body, { a: 1 });
  await assertRejects(() =>
    readJsonObject(
      new Request("https://edge.test", { method: "POST", body: "[]" }),
    )
  );
});

Deno.test("validation rejects bad identity and browser-supplied actor fields", () => {
  assertEquals(normalizedEmail("  USER@Example.TEST "), "user@example.test");
  assertThrows(() => normalizedEmail("bad"));
  assertEquals(
    uuidValue("11111111-1111-4111-8111-111111111111"),
    "11111111-1111-4111-8111-111111111111",
  );
  assertThrows(() => uuidValue("not-a-uuid"));
  assertEquals(reason("  duplicate request "), "duplicate request");
  assertEquals(fullName(" Client Name "), "Client Name");
  assertThrows(() => reason(" "));
  assertThrows(() =>
    rejectUnknownFields({
      email: "a@example.test",
      actor_id: "11111111-1111-4111-8111-111111111111",
    }, ["email"])
  );
});

Deno.test("token helper uses 32 bytes, URL-safe base64, SHA-256, and bytea hex", async () => {
  const token = generateInvitationToken();
  assert(/^[A-Za-z0-9_-]+$/.test(token));
  assert(!token.includes("="));
  const decoded = decodeBase64Url(token);
  assertEquals(decoded.length, 32);
  assertThrows(() => decodeBase64Url(`${token}=`));
  assertThrows(() => decodeBase64Url("abc"));
  const digest = await sha256Digest(decoded);
  assertEquals(digest.length, 32);
  assert(/^\\x[0-9a-f]{64}$/.test(byteaHex(digest)));
});

Deno.test("invitation URL is built only from trusted base URL and fixed path", () => {
  const token = generateInvitationToken();
  const url = invitationUrl("https://app.example.test/base", token);
  assertEquals(url.origin, "https://app.example.test");
  assertEquals(url.pathname, "/accept-invitation");
  assertEquals(url.searchParams.get("token"), token);
  assertThrows(() => invitationUrl("https://app.example.test", "bad/token"));
});

Deno.test("redaction removes sensitive recursive values", () => {
  const output = redact({
    authorization: "Bearer abc.def.ghi",
    nested: {
      message:
        "visit https://app.example.test/accept-invitation?token=secret and OTP 123456",
      safe: "ok",
    },
  });
  const text = JSON.stringify(output);
  assert(!text.includes("abc.def.ghi"));
  assert(!text.includes("secret"));
  assert(!text.includes("123456"));
  assert(text.includes("ok"));
});

async function signHs256Jwt(
  payload: Record<string, unknown>,
  secret: string,
  kid: string,
): Promise<string> {
  const header = { alg: "HS256", typ: "JWT", kid };
  const encodedHeader = btoa(JSON.stringify(header)).replaceAll("+", "-")
    .replaceAll("/", "_").replace(/=+$/, "");
  const encodedPayload = btoa(JSON.stringify(payload)).replaceAll("+", "-")
    .replaceAll("/", "_").replace(/=+$/, "");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
    ),
  );
  const encodedSignature = btoa(String.fromCharCode(...signature)).replaceAll(
    "+",
    "-",
  ).replaceAll("/", "_").replace(/=+$/, "");
  return `${encodedHeader}.${encodedPayload}.${encodedSignature}`;
}

Deno.test("auth helper extracts verified claims and creates service client only after auth", async () => {
  const secret = "local-test-secret-with-at-least-32-bytes";
  const kid = "test-key";
  const jwks = {
    keys: [{
      kty: "oct",
      alg: "HS256",
      kid,
      k: btoa(secret).replaceAll("+", "-").replaceAll("/", "_").replace(
        /=+$/,
        "",
      ),
    }],
  };
  const env = {
    ...loadAppEnv(testEnv({
      SUPABASE_SERVICE_ROLE_KEY: "server-only-placeholder",
    })),
    jwks,
  };
  await assertRejects(
    () => authenticateRequest(new Request("https://edge.test"), env),
    "Authentication",
  );
  const actorId = "11111111-1111-4111-8111-111111111111";
  const jwt = await signHs256Jwt(
    {
      sub: actorId,
      role: "authenticated",
      email: "owner@example.test",
      exp: Math.floor(Date.now() / 1000) + 300,
    },
    secret,
    kid,
  );
  const context = await authenticateRequest(
    new Request("https://edge.test", {
      headers: { Authorization: `Bearer ${jwt}` },
    }),
    env,
  );
  assertEquals(context.actorAuthSubject, actorId);
  assertEquals(context.context.authMode, "user");
  assert(context.serviceClient);
});

Deno.test("denial-log helper restricts codes and masks metadata", () => {
  const args = deniedLogArgs({
    action: "client_invitation_create",
    entityType: "user_invitation",
    reasonCode: "authorization_denied",
    metadata: { token: "secret", safe: "ok" },
  });
  assertEquals(args.metadata, { token: "[REDACTED]", safe: "ok" });
  assertThrows(() =>
    deniedLogArgs({
      action: "raw_sql",
      entityType: "user",
      reasonCode: "authorization_denied",
    })
  );
});
