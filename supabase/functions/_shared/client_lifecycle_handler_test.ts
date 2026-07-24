import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { unauthorized } from "./errors.ts";
import { createLifecycleHandler } from "./client_lifecycle_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000001";
const clientUserId = "10000000-0000-4000-8000-000000000001";
const authSubject = "20000000-0000-4000-8000-000000000001";

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

function assertNotIncludes(actual: string, fragment: string): void {
  if (actual.includes(fragment)) {
    throw new Error(`Expected output not to include ${fragment}`);
  }
}

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
  return new Request("http://127.0.0.1:54321/functions/v1/lifecycle", {
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
  rpcErrors?: Record<string, { code?: string; message?: string }>;
  authErrors?: ({ code?: string; message?: string } | null)[];
  context?: Record<string, unknown>;
}) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> => {
    options.calls.push("authenticate");
    const serviceClient = {
      auth: {
        admin: {
          updateUserById: (
            _userId: string,
            attributes: { ban_duration: string },
          ) => {
            options.calls.push(
              `auth:updateUserById:${attributes.ban_duration}`,
            );
            const error = options.authErrors?.shift() ?? null;
            return Promise.resolve({
              data: {
                user: { id: _userId, banned_until: attributes.ban_duration },
              },
              error,
            });
          },
        },
      },
      rpc: (name: string) => {
        options.calls.push(`rpc:${name}`);
        const error = options.rpcErrors?.[name] ?? null;
        if (error) {
          return Promise.resolve({ data: null, error });
        }
        if (name === "server_client_identity_context") {
          return Promise.resolve({
            data: [
              options.context ?? {
                client_user_id: clientUserId,
                auth_subject: authSubject,
                normalized_email: "client@example.test",
                account_status: "ACTIVE",
                is_active: true,
                latest_invitation_id: null,
                latest_invitation_status: null,
              },
            ],
            error: null,
          });
        }
        if (name === "server_suspend_client_account") {
          return Promise.resolve({ data: clientUserId, error: null });
        }
        if (name === "server_disable_client_account") {
          return Promise.resolve({ data: clientUserId, error: null });
        }
        if (name === "server_reactivate_client_account") {
          return Promise.resolve({ data: clientUserId, error: null });
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

function validBody(): Record<string, unknown> {
  return { client_user_id: clientUserId, reason: " lifecycle reason " };
}

Deno.test("lifecycle rejects bad Origin before authentication and service client creation", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("suspend-client-account", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request(validBody(), {
    headers: { Origin: "https://blocked.example" },
  }));
  assertEquals(response.status, 403);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), null);
  assertEquals(calls, []);
});

Deno.test("lifecycle handles allowed OPTIONS through shared CORS", async () => {
  const handler = createLifecycleHandler("disable-client-account", {
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
  assertEquals(response.headers.get("Vary"), "Origin");
});

Deno.test("lifecycle maps missing and malformed JWT to safe 401", async () => {
  const handler = createLifecycleHandler("suspend-client-account", {
    loadEnv: env,
    authenticate: () => {
      throw unauthorized();
    },
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 401);
  assertEquals(body.code, "unauthorized");
});

Deno.test("lifecycle validates strict fields, UUIDs, and trimmed nonblank reason", async () => {
  const handler = createLifecycleHandler("suspend-client-account", {
    loadEnv: env,
    authenticate: mockAuth({ calls: [] }),
  });
  for (
    const body of [
      { client_user_id: clientUserId, reason: "x", actor_id: actor },
      { client_user_id: "not-a-uuid", reason: "x" },
      { client_user_id: clientUserId, reason: "   " },
      { client_user_id: clientUserId, reason: "x", status: "ACTIVE" },
    ]
  ) {
    const response = await handler(request(body));
    assertEquals(response.status, 422);
  }
});

Deno.test("suspend uses database-first ordering and applies long Auth ban", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("suspend-client-account", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data, {
    client_user_id: clientUserId,
    status: "SUSPENDED",
    auth_update: "applied",
  });
  assertEquals(calls, [
    "authenticate",
    "rpc:server_client_identity_context",
    "rpc:server_suspend_client_account",
    "auth:updateUserById:876000h",
  ]);
});

Deno.test("disable uses database-first ordering and applies terminal Auth ban", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("disable-client-account", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.status, "DISABLED");
  assertEquals(calls, [
    "authenticate",
    "rpc:server_client_identity_context",
    "rpc:server_disable_client_account",
    "auth:updateUserById:876000h",
  ]);
});

Deno.test("reactivate uses Auth-first ordering before database reactivation", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("reactivate-client-account", {
    loadEnv: env,
    authenticate: mockAuth({
      calls,
      context: {
        auth_subject: authSubject,
        account_status: "SUSPENDED",
        is_active: false,
      },
    }),
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.status, "ACTIVE");
  assertEquals(calls, [
    "authenticate",
    "rpc:server_client_identity_context",
    "auth:updateUserById:none",
    "rpc:server_reactivate_client_account",
  ]);
});

Deno.test("suspend and disable skip Auth update when database RPC fails", async () => {
  for (
    const kind of ["suspend-client-account", "disable-client-account"] as const
  ) {
    const calls: string[] = [];
    const gateway = kind === "suspend-client-account"
      ? "server_suspend_client_account"
      : "server_disable_client_account";
    const handler = createLifecycleHandler(kind, {
      loadEnv: env,
      authenticate: mockAuth({
        calls,
        rpcErrors: { [gateway]: { code: "23514" } },
      }),
    });
    const response = await handler(request(validBody()));
    assertEquals(response.status, 422);
    assertEquals(calls.includes("auth:updateUserById:876000h"), false);
  }
});

Deno.test("Auth failure after suspend or disable returns safe consistency warning", async () => {
  for (
    const kind of ["suspend-client-account", "disable-client-account"] as const
  ) {
    const handler = createLifecycleHandler(kind, {
      loadEnv: env,
      authenticate: mockAuth({
        calls: [],
        authErrors: [{ code: "provider_failed", message: "secret stack" }],
      }),
    });
    const response = await handler(request(validBody()));
    const body = await response.json();
    assertEquals(response.status, 200);
    assertEquals(body.data.auth_update, "warning");
    assertNotIncludes(JSON.stringify(body), "provider_failed");
  }
});

Deno.test("failed reactivation database call restores Auth ban when compensation succeeds", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("reactivate-client-account", {
    loadEnv: env,
    authenticate: mockAuth({
      calls,
      context: {
        auth_subject: authSubject,
        account_status: "SUSPENDED",
        is_active: false,
      },
      rpcErrors: { server_reactivate_client_account: { code: "23514" } },
    }),
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.auth_update, "compensated");
  assertEquals(body.data.status, "SUSPENDED");
  assertEquals(calls, [
    "authenticate",
    "rpc:server_client_identity_context",
    "auth:updateUserById:none",
    "rpc:server_reactivate_client_account",
    "auth:updateUserById:876000h",
  ]);
});

Deno.test("failed reactivation reports compensation failure without claiming active status", async () => {
  const handler = createLifecycleHandler("reactivate-client-account", {
    loadEnv: env,
    authenticate: mockAuth({
      calls: [],
      context: {
        auth_subject: authSubject,
        account_status: "SUSPENDED",
        is_active: false,
      },
      rpcErrors: { server_reactivate_client_account: { code: "23514" } },
      authErrors: [null, { code: "compensation_failed" }],
    }),
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.auth_update, "compensation_failed");
  assertEquals(body.data.status, "SUSPENDED");
});

Deno.test("disabled terminal state is not reactivated", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("reactivate-client-account", {
    loadEnv: env,
    authenticate: mockAuth({
      calls,
      context: {
        auth_subject: authSubject,
        account_status: "DISABLED",
        is_active: false,
      },
    }),
  });
  const response = await handler(request(validBody()));
  assertEquals(response.status, 422);
  assertEquals(calls.includes("auth:updateUserById:none"), false);
});

Deno.test("database authorization denials trigger best-effort denied-log follow-up", async () => {
  const calls: string[] = [];
  const handler = createLifecycleHandler("disable-client-account", {
    loadEnv: env,
    authenticate: mockAuth({
      calls,
      rpcErrors: { server_disable_client_account: { code: "42501" } },
    }),
  });
  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 401);
  assertEquals(
    calls.includes("rpc:server_record_denied_privileged_operation"),
    true,
  );
  assertNotIncludes(JSON.stringify(body), "42501");
});

Deno.test("lifecycle responses do not leak service keys, JWTs, or raw request bodies", async () => {
  const handler = createLifecycleHandler("suspend-client-account", {
    loadEnv: env,
    authenticate: mockAuth({
      calls: [],
      rpcErrors: {
        server_suspend_client_account: {
          code: "23514",
          message: "raw body secret",
        },
      },
    }),
  });
  const response = await handler(request({
    client_user_id: clientUserId,
    reason: "contains service-role-placeholder and Bearer verified",
  }));
  const text = await response.text();
  assertNotIncludes(text, "service-role-placeholder");
  assertNotIncludes(text, "Bearer verified");
  assertNotIncludes(text, "raw body secret");
});
