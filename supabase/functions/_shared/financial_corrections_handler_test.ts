import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { createFinancialCorrectionsHandler } from "./financial_corrections_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000001";
const eventId = "10000000-0000-4000-8000-000000000001";
const txId = "20000000-0000-4000-8000-000000000001";
const accountId = "30000000-0000-4000-8000-000000000001";

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
  return new Request(
    "http://127.0.0.1:54321/functions/v1/financial-corrections",
    {
      method: "POST",
      headers: {
        Origin: origin,
        "content-type": "application/json",
        authorization: "Bearer verified",
      },
      body: JSON.stringify(body),
    },
  );
}

function mockAuth(calls: Record<string, unknown>[]) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> =>
    Promise.resolve({
      actorAuthSubject: actor,
      serviceClient: {
        rpc: (name: string, args: Record<string, unknown>) => {
          calls.push({ name, ...args });
          if (name.includes("source")) {
            return Promise.resolve({ data: [source()], error: null });
          }
          if (name.includes("reversal_detail")) {
            return Promise.resolve({ data: [reversal()], error: null });
          }
          if (name.includes("adjustment_detail")) {
            return Promise.resolve({ data: [adjustment()], error: null });
          }
          if (name.includes("adjustment_list")) {
            return Promise.resolve({ data: [adjustment()], error: null });
          }
          if (name.includes("reversal_list")) {
            return Promise.resolve({ data: [reversal()], error: null });
          }
          return Promise.resolve({
            data: [{ financial_event_id: eventId, version_number: 2 }],
            error: null,
          });
        },
      },
    } as unknown as AuthenticatedContext);
}

Deno.test("financial correction gateway derives actor and rejects spoofed fields", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createFinancialCorrectionsHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request({
    action: "create_reversal",
    original_transaction_id: txId,
    reversal_date: "2026-08-17",
    reason: "posted mistake",
    owner_id: actor,
  }));
  assertEquals(response.status, 422);
});

Deno.test("financial reversal create preserves exact money style inputs", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createFinancialCorrectionsHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request({
    action: "create_reversal",
    original_transaction_id: txId,
    reversal_date: "2026-08-17",
    reason: "posted mistake",
  }));
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_create_reversal");
  assertEquals(calls[0].p_verified_owner_auth_subject, actor);
});

Deno.test("financial adjustment rejects numeric floats", async () => {
  const handler = createFinancialCorrectionsHandler({
    loadEnv: env,
    authenticate: mockAuth([]),
  });
  const response = await handler(request({
    action: "create_adjustment",
    financial_account_id: accountId,
    direction: "INCREASE",
    amount: 10.5,
    adjustment_date: "2026-08-17",
    reporting_currency_code: "USD",
    reason: "delta",
  }));
  assertEquals(response.status, 422);
});

function source() {
  return {
    financial_event_id: eventId,
    event_number: "FE-000001",
    event_type: "OPENING_BALANCE",
    financial_transaction_id: txId,
    transaction_number: "FT-000001",
    amount: "10.50",
    currency_code: "USD",
    event_date: "2026-08-17",
    label: "OPENING_BALANCE FE-000001 / FT-000001",
    can_reverse: true,
    can_adjust: true,
    reversal_recorded: false,
    adjustment_recorded: false,
  };
}

function reversal() {
  return {
    financial_event_id: eventId,
    event_number: "FE-000002",
    financial_transaction_id: txId,
    transaction_number: "FT-000002",
    original_transaction_id: txId,
    reason: "mistake",
    full_reversal: true,
    reversal_date: "2026-08-17",
    reporting_currency_code: "USD",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    description: null,
    submitted_at: "2026-08-17T00:00:00Z",
    approved_at: null,
    rejected_at: null,
    rejection_reason: null,
    version_number: 2,
  };
}

function adjustment() {
  return {
    financial_event_id: eventId,
    event_number: "FE-000003",
    financial_transaction_id: txId,
    transaction_number: "FT-000003",
    adjusted_transaction_id: txId,
    financial_account_id: accountId,
    direction: "INCREASE",
    amount: "10.50",
    currency_code: "USD",
    adjustment_date: "2026-08-17",
    reason: "delta",
    reporting_currency_code: "USD",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    description: null,
    submitted_at: "2026-08-17T00:00:00Z",
    approved_at: null,
    rejected_at: null,
    rejection_reason: null,
    version_number: 2,
  };
}
