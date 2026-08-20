import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { createClientPaymentsHandler } from "./client_payments_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000001";
const eventId = "10000000-0000-4000-8000-000000000001";
const paymentId = "20000000-0000-4000-8000-000000000001";
const projectId = "30000000-0000-4000-8000-000000000001";
const accountId = "40000000-0000-4000-8000-000000000001";
const requestId = "50000000-0000-4000-8000-000000000001";
const clientId = "60000000-0000-4000-8000-000000000001";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
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

function request(body: unknown): Request {
  return new Request("http://127.0.0.1:54321/functions/v1/client-payments", {
    method: "POST",
    headers: {
      Origin: origin,
      "content-type": "application/json",
      authorization: "Bearer verified",
    },
    body: JSON.stringify(body),
  });
}

function mockAuth(calls: Record<string, unknown>[]) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> =>
    Promise.resolve({
      actorAuthSubject: actor,
      serviceClient: {
        rpc: (name: string, args: Record<string, unknown>) => {
          calls.push({ name, ...args });
          if (name === "server_owner_client_payment_detail") {
            return Promise.resolve({ data: [paymentDetail()], error: null });
          }
          if (name === "server_owner_payment_request_detail") {
            return Promise.resolve({
              data: [paymentRequestDetail()],
              error: null,
            });
          }
          if (name === "server_owner_client_payment_list") {
            return Promise.resolve({ data: [paymentSummary()], error: null });
          }
          if (name === "server_owner_payment_request_list") {
            return Promise.resolve({
              data: [paymentRequestSummary()],
              error: null,
            });
          }
          if (name === "server_owner_project_record_detail") {
            return Promise.resolve({ data: [projectDetail()], error: null });
          }
          if (name === "server_owner_client_record_detail") {
            return Promise.resolve({ data: [clientDetail()], error: null });
          }
          if (name.includes("payment_request")) {
            return Promise.resolve({
              data: [{
                payment_request_id: requestId,
                request_number: "PR-000001",
                status: "DRAFT",
                version_number: 2,
              }],
              error: null,
            });
          }
          return Promise.resolve({
            data: [{
              financial_event_id: eventId,
              client_payment_id: paymentId,
              version_number: 2,
            }],
            error: null,
          });
        },
      },
    } as unknown as AuthenticatedContext);
}

Deno.test("client payment gateway derives owner subject and preserves exact money", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createClientPaymentsHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request({
    action: "create",
    project_id: projectId,
    amount: "100.25",
    currency_code: "USD",
    received_date: "2026-08-15",
    received_account_id: accountId,
    payment_reference: "REF-1",
  }));
  const json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_create_client_payment");
  assertEquals(calls[0].p_verified_owner_auth_subject, actor);
  assertEquals(calls[0].p_amount, "100.25");
  assert(json.data.payment.financial_event_id === eventId);
});

Deno.test("client payment gateway rejects spoofed owner fields and numeric money", async () => {
  const handler = createClientPaymentsHandler({
    loadEnv: env,
    authenticate: mockAuth([]),
  });
  const response = await handler(request({
    action: "create",
    p_verified_owner_auth_subject: actor,
    project_id: projectId,
    amount: 100.25,
    currency_code: "USD",
    received_date: "2026-08-15",
  }));
  assertEquals(response.status, 422);
});

Deno.test("client payment approval denial is mapped safely", async () => {
  const handler = createClientPaymentsHandler({
    loadEnv: env,
    authenticate: () =>
      Promise.resolve({
        actorAuthSubject: actor,
        serviceClient: {
          rpc: () =>
            Promise.resolve({
              data: null,
              error: {
                code: "42501",
                message: "Client payment requires a different Owner.",
              },
            }),
        },
      } as unknown as AuthenticatedContext),
  });
  const response = await handler(request({
    action: "approve",
    financial_event_id: eventId,
    expected_version_number: 2,
  }));
  const json = await response.json();
  assertEquals(response.status, 401);
  assertEquals(String(json.error).includes("different Owner"), false);
});

Deno.test("payment request gateway uses approved owner RPCs", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createClientPaymentsHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request({
    action: "request_create",
    project_id: projectId,
    requested_amount: "250.00",
    currency_code: "SAR",
    request_date: "2026-08-15",
    due_date: "2026-08-30",
    description: "Milestone payment",
  }));
  const json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_create_payment_request");
  assertEquals(calls[0].p_verified_owner_auth_subject, actor);
  assertEquals(calls[0].p_requested_amount, "250.00");
  assert(json.data.request.payment_request_id === requestId);
});

Deno.test("Owner financial rows expose sanitized Project and Client labels", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createClientPaymentsHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const cases = [
    { action: "list" },
    { action: "detail", financial_event_id: eventId },
    { action: "request_list" },
    { action: "request_detail", payment_request_id: requestId },
  ];
  for (const body of cases) {
    const response = await handler(request(body));
    const json = await response.json();
    assertEquals(response.status, 200);
    const row = json.data.payment ?? json.data.request ??
      json.data.payments?.[0] ?? json.data.requests?.[0];
    assertEquals(row.project_number, "PRJ-2026-0001");
    assertEquals(row.project_name, "Villa Renovation");
    assertEquals(row.client_number, "CL-000001");
    assertEquals(row.client_name, "Acme Client");
    assert(String(JSON.stringify(row)).includes("internal_notes") === false);
    assert(
      String(JSON.stringify(row)).includes("private@example.test") === false,
    );
  }
  const lookupCalls = calls.filter((call) =>
    call.name === "server_owner_project_record_detail" ||
    call.name === "server_owner_client_record_detail"
  );
  assert(lookupCalls.length === 8);
  assert(
    lookupCalls.every((call) => call.p_verified_owner_auth_subject === actor),
  );
});

Deno.test("Client cannot use Owner financial metadata lookup behavior", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createClientPaymentsHandler({
    loadEnv: env,
    authenticate: () =>
      Promise.resolve({
        actorAuthSubject: "70000000-0000-4000-8000-000000000001",
        serviceClient: {
          rpc: (name: string, args: Record<string, unknown>) => {
            calls.push({ name, ...args });
            if (name === "server_owner_client_payment_list") {
              return Promise.resolve({ data: [paymentSummary()], error: null });
            }
            return Promise.resolve({
              data: null,
              error: { code: "42501", message: "Owner role required." },
            });
          },
        },
      } as unknown as AuthenticatedContext),
  });
  const response = await handler(request({ action: "list" }));
  const json = await response.json();
  assertEquals(response.status, 401);
  assertEquals(calls[1].name, "server_owner_project_record_detail");
  assert(String(JSON.stringify(json)).includes("Owner role") === false);
});

function paymentSummary() {
  return {
    client_payment_id: paymentId,
    financial_event_id: eventId,
    event_number: "FE-000001",
    financial_transaction_id: null,
    transaction_number: null,
    project_id: projectId,
    client_id: clientId,
    amount: "100.25",
    currency_code: "USD",
    received_date: "2026-08-15",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    is_client_submitted: true,
    version_number: 2,
  };
}

function paymentDetail() {
  return {
    ...paymentSummary(),
    received_account_id: accountId,
    payment_reference: "REF-1",
    payer_name: null,
    submitted_by_client_user_id: null,
    notes: null,
    reporting_currency_code: "USD",
    submitted_at: "2026-08-15T00:00:00Z",
    approved_at: null,
    rejected_at: null,
    rejection_reason: null,
  };
}

function paymentRequestSummary() {
  return {
    payment_request_id: requestId,
    request_number: "PR-000001",
    project_id: projectId,
    client_id: clientId,
    requested_amount: "250.00",
    currency_code: "SAR",
    request_date: "2026-08-15",
    due_date: "2026-08-30",
    status: "DRAFT",
    effective_status: "DRAFT",
    sent_at: null,
    viewed_at: null,
    cancelled_at: null,
    version_number: 2,
  };
}

function paymentRequestDetail() {
  return {
    ...paymentRequestSummary(),
    description: "Milestone payment",
    cancelled_by: null,
    cancellation_reason: null,
    created_at: "2026-08-15T00:00:00Z",
    created_by: actor,
    updated_at: "2026-08-15T00:00:00Z",
    updated_by: actor,
    paid_amount: "0",
    remaining_amount: "250.00",
  };
}

function projectDetail() {
  return {
    id: projectId,
    client_id: clientId,
    project_number: "PRJ-2026-0001",
    name: "Villa Renovation",
    internal_notes: "must not leak",
  };
}

function clientDetail() {
  return {
    id: clientId,
    client_number: "CL-000001",
    display_name: "Acme Client",
    email: "private@example.test",
    internal_notes: "must not leak",
  };
}
