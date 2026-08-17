import type { AppEnv } from "../_shared/env.ts";
import type { AuthenticatedContext } from "../_shared/auth.ts";
import { unauthorized } from "../_shared/errors.ts";
import { createClientProjectsGateway } from "./index.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000001";
const clientId = "10000000-0000-4000-8000-000000000001";
const projectId = "20000000-0000-4000-8000-000000000001";

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
  headers: Record<string, string> = {},
) {
  return new Request("http://local/functions/v1/client-projects", {
    method: "POST",
    headers: {
      origin,
      "content-type": "application/json",
      authorization: "Bearer verified",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function mockAuth(
  calls: string[],
  rpcError?: { code?: string; message?: string },
) {
  return (): Promise<AuthenticatedContext> => {
    calls.push("authenticate");
    const serviceClient = {
      auth: {
        admin: {
          generateLink: () => {
            calls.push("generateLink");
            return Promise.resolve({
              data: { user: { id: "30000000-0000-4000-8000-000000000001" } },
              error: null,
            });
          },
          inviteUserByEmail: () => {
            calls.push("inviteUserByEmail");
            return Promise.resolve({ data: {}, error: null });
          },
        },
      },
      rpc: (name: string) => {
        calls.push(`rpc:${name}`);
        if (rpcError) return Promise.resolve({ data: null, error: rpcError });
        if (name.includes("client_record_list")) {
          return Promise.resolve({ data: [clientRow()], error: null });
        }
        if (name.includes("client_record_detail")) {
          return Promise.resolve({ data: [clientRow()], error: null });
        }
        if (name.includes("project_record_list")) {
          return Promise.resolve({ data: [projectRow()], error: null });
        }
        if (name.includes("project_record_detail")) {
          return Promise.resolve({ data: [projectRow()], error: null });
        }
        if (name.includes("create_client_record_invitation")) {
          return Promise.resolve({
            data: [{
              invited_user_id: "30000000-0000-4000-8000-000000000002",
              invitation_id: "40000000-0000-4000-8000-000000000001",
              expires_at: "2026-08-24T00:00:00Z",
            }],
            error: null,
          });
        }
        if (name.includes("change_project_status")) {
          return Promise.resolve({
            data: [{
              project_id: projectId,
              status: "ACTIVE",
              version_number: 2,
            }],
            error: null,
          });
        }
        return Promise.resolve({ data: [], error: null });
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

Deno.test("Owner gateway rejects bad Origin before authentication", async () => {
  const calls: string[] = [];
  const handler = createClientProjectsGateway({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(
    request({ action: "client_list" }, { origin: "https://evil.example" }),
  );
  assertEquals(response.status, 403);
  assertEquals(calls, []);
});

Deno.test("Owner gateway maps unauthenticated callers safely", async () => {
  const handler = createClientProjectsGateway({
    loadEnv: env,
    authenticate: () => {
      throw unauthorized();
    },
  });
  const response = await handler(request({ action: "client_list" }));
  const body = await response.json();
  assertEquals(response.status, 401);
  assertEquals(body.code, "unauthorized");
});

Deno.test("Owner gateway rejects actor spoofing and unknown fields", async () => {
  const calls: string[] = [];
  const handler = createClientProjectsGateway({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(
    request({ action: "client_list", p_verified_owner_auth_subject: actor }),
  );
  const body = await response.json();
  assertEquals(response.status, 422);
  assertEquals(body.message, "Request contains unsupported fields.");
});

Deno.test("Client list and project detail use server RPCs and sanitized projections", async () => {
  const calls: string[] = [];
  const handler = createClientProjectsGateway({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const clients = await (await handler(request({ action: "client_list" })))
    .json();
  const project = await (await handler(
    request({ action: "project_detail", project_id: projectId }),
  )).json();
  assertEquals(clients.data.clients[0].client_number, "CL-000001");
  assertEquals(project.data.project.project_number, "PRJ-2026-0001");
  assertEquals("created_by" in project.data.project, false);
});

Deno.test("Invitation send links to Client record wrapper and emails after database success", async () => {
  const calls: string[] = [];
  const handler = createClientProjectsGateway({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(
    request({ action: "invitation_send", client_id: clientId }),
  );
  assertEquals(response.status, 200);
  assertEquals(
    calls.includes("rpc:server_create_client_record_invitation"),
    true,
  );
  assertEquals(calls.at(-1), "inviteUserByEmail");
});

Deno.test("Project transitions call authoritative lifecycle RPC and authorization errors deny deferred roles", async () => {
  const denied = createClientProjectsGateway({
    loadEnv: env,
    authenticate: mockAuth([], { code: "42501" }),
  });
  assertEquals((await denied(request({ action: "project_list" }))).status, 401);

  const calls: string[] = [];
  const handler = createClientProjectsGateway({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request({
    action: "project_transition",
    project_id: projectId,
    expected_version_number: 1,
    new_status: "ACTIVE",
  }));
  assertEquals(response.status, 200);
  assertEquals(calls.includes("rpc:server_change_project_status"), true);
});

function clientRow() {
  return {
    id: clientId,
    client_number: "CL-000001",
    display_name: "Acme Client",
    email: "client@example.com",
    phone: null,
    status: "ACTIVE",
    is_active: true,
    portal_user_id: null,
    version_number: 1,
    created_by: "masked-away",
  };
}

function projectRow() {
  return {
    id: projectId,
    client_id: clientId,
    project_number: "PRJ-2026-0001",
    name: "Villa Build",
    status: "APPROVED",
    reporting_currency_code: "SGD",
    version_number: 1,
    created_by: "masked-away",
  };
}
