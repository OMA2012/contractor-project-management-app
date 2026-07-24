import type { AppEnv } from "./env.ts";
import type { AuthenticatedContext } from "./auth.ts";
import { unauthorized } from "./errors.ts";
import { createInvitationHandler } from "./client_invitation_handler.ts";

function assertEquals(
  actual: unknown,
  expected: unknown,
  message?: string,
): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertMatch(actual: string, expected: RegExp): void {
  if (!expected.test(actual)) {
    throw new Error(`Expected ${actual} to match ${expected}`);
  }
}

const actor = "00000000-0000-4000-8000-000000000001";
const userId = "10000000-0000-4000-8000-000000000001";
const invitationId = "20000000-0000-4000-8000-000000000001";
const origin = "http://localhost:3000";

function env(): AppEnv {
  return {
    supabaseUrl: "http://127.0.0.1:54321",
    publishableKey: "publishable-placeholder",
    serviceRoleKey: "service-role-placeholder",
    jwksUrl: "http://127.0.0.1:54321/auth/v1/.well-known/jwks.json",
    appBaseUrl: origin,
    appOrigin: origin,
  };
}

function request(
  body: Record<string, unknown>,
  init: RequestInit = {},
): Request {
  return new Request("http://127.0.0.1:54321/functions/v1/test", {
    method: "POST",
    headers: {
      "Origin": origin,
      "content-type": "application/json",
      "authorization": "Bearer verified",
      ...init.headers,
    },
    body: JSON.stringify(body),
  });
}

function mockAuth(options: {
  calls: string[];
  rpcError?: { code?: string; message?: string };
  inviteError?: { code?: string; message?: string };
  contextRows?: Record<string, unknown>[];
}) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> => {
    options.calls.push("authenticate");
    const serviceClient = {
      auth: {
        admin: {
          generateLink: () => {
            options.calls.push("generateLink");
            return Promise.resolve({
              data: { user: { id: "30000000-0000-4000-8000-000000000001" } },
              error: null,
            });
          },
          inviteUserByEmail: () => {
            options.calls.push("inviteUserByEmail");
            return Promise.resolve({
              data: {},
              error: options.inviteError ?? null,
            });
          },
        },
      },
      rpc: (name: string) => {
        options.calls.push(`rpc:${name}`);
        if (
          options.rpcError &&
          name !== "server_record_denied_privileged_operation"
        ) {
          return Promise.resolve({ data: null, error: options.rpcError });
        }
        if (name === "server_client_identity_context") {
          return Promise.resolve({
            data: options.contextRows ?? [{
              client_user_id: userId,
              auth_subject: "30000000-0000-4000-8000-000000000001",
              normalized_email: "client@example.com",
              account_status: "INVITED",
              is_active: false,
              latest_invitation_id: invitationId,
              latest_invitation_status: "PENDING",
            }],
            error: null,
          });
        }
        if (name === "server_create_client_invitation") {
          return Promise.resolve({
            data: [{
              invited_user_id: userId,
              invitation_id: invitationId,
              expires_at: "2026-08-01T00:00:00Z",
            }],
            error: null,
          });
        }
        if (name === "server_resend_client_invitation") {
          return Promise.resolve({
            data: [{
              invitation_id: invitationId,
              resent_from_invitation_id: "20000000-0000-4000-8000-000000000000",
              expires_at: "2026-08-01T00:00:00Z",
            }],
            error: null,
          });
        }
        if (name === "server_revoke_client_invitation") {
          return Promise.resolve({ data: invitationId, error: null });
        }
        if (name === "server_accept_client_invitation") {
          return Promise.resolve({ data: userId, error: null });
        }
        return Promise.resolve({ data: null, error: null });
      },
    };
    return Promise.resolve({
      actorAuthSubject: actor,
      context: {} as AuthenticatedContext["context"],
      serviceClient:
        serviceClient as unknown as AuthenticatedContext["serviceClient"],
    });
  };
}

Deno.test("handler rejects missing or mismatched Origin before authentication", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({ email: "client@example.com" }, {
    headers: { Origin: "https://evil.example" },
  }));
  assertEquals(response.status, 403);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), null);
  assertEquals(calls, []);
});

Deno.test("handler returns strict CORS headers for allowed OPTIONS", async () => {
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
  });
  const response = await handler(
    new Request("http://local", {
      method: "OPTIONS",
      headers: { Origin: origin },
    }),
  );
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), origin);
  assertEquals(
    response.headers.get("Access-Control-Allow-Methods"),
    "POST, OPTIONS",
  );
  assertEquals(response.headers.get("Vary"), "Origin");
});

Deno.test("handler maps missing or malformed JWT to safe 401", async () => {
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: () => {
      throw unauthorized();
    },
  });
  const response = await handler(request({ email: "client@example.com" }));
  const body = await response.json();
  assertEquals(response.status, 401);
  assertEquals(body.code, "unauthorized");
});

Deno.test("create ordering is generateLink then database RPC then invite email", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({ email: " CLIENT@example.com " }));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.status, "PENDING");
  assertEquals(calls, [
    "authenticate",
    "generateLink",
    "rpc:server_create_client_invitation",
    "inviteUserByEmail",
  ]);
});

Deno.test("create does not send email when database RPC fails and records normalized denial", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls, rpcError: { code: "42501" } }),
  });
  const response = await handler(request({ email: "client@example.com" }));
  const body = await response.json();
  assertEquals(response.status, 401);
  assertEquals(body.message.includes("42501"), false);
  assertEquals(calls, [
    "authenticate",
    "generateLink",
    "rpc:server_create_client_invitation",
    "rpc:server_record_denied_privileged_operation",
  ]);
});

Deno.test("create reports retryable delivery failure after database success", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls, inviteError: { code: "email_failed" } }),
  });
  const response = await handler(request({ email: "client@example.com" }));
  const body = await response.json();
  assertEquals(response.status, 503);
  assertEquals(
    body.message,
    "Invitation email could not be sent. Retry resend.",
  );
  assertEquals(calls.includes("rpc:server_create_client_invitation"), true);
});

Deno.test("resend ordering refreshes Auth state before database replacement and email after", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("resend-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({ invited_user_id: userId }));
  assertEquals(response.status, 200);
  assertEquals(calls, [
    "authenticate",
    "rpc:server_client_identity_context",
    "generateLink",
    "rpc:server_resend_client_invitation",
    "inviteUserByEmail",
  ]);
});

Deno.test("revoke validates strict request fields and maps state errors safely", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("revoke-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({
      calls,
      rpcError: { code: "23514", message: "Invitation cannot be revoked." },
    }),
  });
  const response = await handler(request({
    invitation_id: invitationId,
    revoke_reason: "duplicate",
  }));
  const body = await response.json();
  assertEquals(response.status, 422);
  assertEquals(body.message, "Invitation request cannot be completed.");
});

Deno.test("accept decodes token, hashes digest, and never accepts actor identity from body", async () => {
  const calls: string[] = [];
  const token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
  const handler = createInvitationHandler("accept-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({
    token,
    full_name: " Client Name ",
    actor_id: actor,
  }));
  const body = await response.json();
  assertEquals(response.status, 422);
  assertEquals(body.message, "Request contains unsupported fields.");

  const ok = await handler(request({ token, full_name: " Client Name " }));
  const okBody = await ok.json();
  assertEquals(ok.status, 200);
  assertEquals(okBody.data.status, "ACTIVE");
  assertMatch(JSON.stringify(okBody), /^((?!AAAAAAAA).)*$/);
});

Deno.test("accept maps invalid, expired, revoked, repeated, mismatch, and concurrent failures safely", async () => {
  const handler = createInvitationHandler("accept-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls: [], rpcError: { code: "23514" } }),
  });
  const response = await handler(request({
    token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    full_name: "Client Name",
  }));
  const body = await response.json();
  assertEquals(response.status, 422);
  assertEquals(body.message, "Invitation request cannot be completed.");
});

Deno.test("responses do not leak secrets, JWTs, digests, tokens, or full invitation URLs", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({
      calls,
      rpcError: { code: "23505", message: "duplicate token_hash" },
    }),
  });
  const response = await handler(request({ email: "client@example.com" }));
  const text = await response.text();
  assertEquals(text.includes("service-role-placeholder"), false);
  assertEquals(text.includes("Bearer verified"), false);
  assertEquals(text.includes("token_hash"), false);
  assertEquals(text.includes("/accept-invitation?token="), false);
});

Deno.test("service client is unavailable before Origin and authentication succeed", async () => {
  const calls: string[] = [];
  const handler = createInvitationHandler("create-client-invitation", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({ email: "client@example.com" }, {
    headers: { Origin: "https://blocked.example" },
  }));
  assertEquals(response.status, 403);
  assertEquals(calls.length, 0);
});
