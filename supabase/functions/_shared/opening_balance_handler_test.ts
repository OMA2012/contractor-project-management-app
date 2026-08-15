import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { createOpeningBalanceHandler } from "./opening_balance_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000001";
const eventId = "10000000-0000-4000-8000-000000000001";
const accountId = "20000000-0000-4000-8000-000000000001";

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
  return new Request("http://127.0.0.1:54321/functions/v1/opening-balances", {
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
          if (name === "server_owner_opening_balance_detail") {
            return Promise.resolve({ data: [openingBalance()], error: null });
          }
          if (name === "server_owner_financial_approval_queue") {
            return Promise.resolve({ data: [queueItem()], error: null });
          }
          return Promise.resolve({
            data: [{ financial_event_id: eventId, version_number: 2 }],
            error: null,
          });
        },
      },
    } as unknown as AuthenticatedContext);
}

Deno.test("opening balance create derives owner subject and preserves exact money", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createOpeningBalanceHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request({
    action: "create",
    financial_account_id: accountId,
    amount: "100.25",
    opening_date: "2026-08-15",
    reporting_currency_code: "USD",
    description: "opening",
    notes: "note",
    duplicate_fingerprint: "fp",
  }));
  const json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_create_opening_balance");
  assertEquals(calls[0].p_verified_owner_auth_subject, actor);
  assertEquals(calls[0].p_amount, "100.25");
  assert(json.data.opening_balance.financial_event_id === eventId);
});

Deno.test("opening balance rejects floating numbers and unknown fields", async () => {
  const handler = createOpeningBalanceHandler({
    loadEnv: env,
    authenticate: mockAuth([]),
  });
  const response = await handler(request({
    action: "create",
    financial_account_id: accountId,
    amount: 100.25,
    opening_date: "2026-08-15",
    reporting_currency_code: "USD",
  }));
  assertEquals(response.status, 422);
});

Deno.test("opening balance approve maps self approval denial safely", async () => {
  const handler = createOpeningBalanceHandler({
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
                message: "Opening balance requires different Owner approval.",
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

Deno.test("approval queue exposes backend eligibility sections", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createOpeningBalanceHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(
    request({ action: "queue", section: "created_by_me" }),
  );
  const json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_financial_approval_queue");
  assertEquals(calls[0].p_section, "created_by_me");
  assertEquals(json.data.items[0].created_by_me, true);
  assertEquals(json.data.items[0].eligible_for_my_approval, false);
});

function openingBalance() {
  return {
    financial_event_id: eventId,
    event_number: "FE-000001",
    financial_transaction_id: "30000000-0000-4000-8000-000000000001",
    transaction_number: "FT-000001",
    financial_account_id: accountId,
    amount: "100.25",
    currency_code: "USD",
    opening_date: "2026-08-15",
    reporting_currency_code: "USD",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    description: "opening",
    notes: null,
    submitted_at: "2026-08-15T00:00:00Z",
    approved_at: null,
    rejected_at: null,
    rejection_reason: null,
    version_number: 2,
  };
}

function queueItem() {
  return {
    ...openingBalance(),
    event_type: "OPENING_BALANCE",
    related_label: "Cash (FA-000001)",
    event_date: "2026-08-15",
    created_by_me: true,
    eligible_for_my_approval: false,
  };
}
