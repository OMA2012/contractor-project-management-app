import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { createAccountTransferHandler } from "./account_transfer_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000011";
const eventId = "10000000-0000-4000-8000-000000000011";
const txId = "20000000-0000-4000-8000-000000000011";
const transferId = "30000000-0000-4000-8000-000000000011";
const sourceId = "40000000-0000-4000-8000-000000000011";
const destinationId = "50000000-0000-4000-8000-000000000011";

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
  return new Request("http://127.0.0.1:54321/functions/v1/account-transfers", {
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
          if (name === "server_owner_account_transfer_list") {
            return Promise.resolve({ data: [summaryRow()], error: null });
          }
          if (name === "server_owner_account_transfer_detail") {
            return Promise.resolve({ data: [detailRow()], error: null });
          }
          return Promise.resolve({ data: [mutationRow()], error: null });
        },
      },
    } as unknown as AuthenticatedContext);
}

Deno.test("account transfer gateway handles authenticated Owner list and detail", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createAccountTransferHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  let response = await handler(request({ action: "list" }));
  let json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_account_transfer_list");
  assertEquals(calls[0].p_verified_owner_auth_subject, actor);
  assertEquals(json.data.account_transfers[0].amount, "123.45");

  response = await handler(
    request({ action: "detail", financial_event_id: eventId }),
  );
  json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[1].name, "server_owner_account_transfer_detail");
  assertEquals(json.data.account_transfer.notes, "private");
});

Deno.test("account transfer create and update preserve exact decimal strings", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createAccountTransferHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request(draftBody("create")));
  const json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_create_account_transfer");
  assertEquals(calls[0].p_amount, "123.45");
  assertEquals(calls[0].p_currency_code, "USD");
  assertEquals(json.data.account_transfer.financial_event_id, eventId);

  await handler(
    request({
      ...draftBody("update"),
      financial_event_id: eventId,
      expected_version_number: 2,
    }),
  );
  assertEquals(calls[1].name, "server_owner_update_account_transfer");
  assertEquals(calls[1].p_expected_version_number, 2);
});

Deno.test("account transfer submit approve and reject use expected workflow RPCs", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createAccountTransferHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  await handler(
    request({
      action: "submit",
      financial_event_id: eventId,
      expected_version_number: 2,
    }),
  );
  await handler(
    request({
      action: "approve",
      financial_event_id: eventId,
      expected_version_number: 3,
    }),
  );
  await handler(
    request({
      action: "reject",
      financial_event_id: eventId,
      expected_version_number: 3,
      rejection_reason: "not valid",
    }),
  );
  assertEquals(calls.map((c) => c.name), [
    "server_owner_submit_account_transfer",
    "server_owner_approve_account_transfer",
    "server_owner_reject_account_transfer",
  ]);
});

Deno.test("account transfer rejects spoofed Owner identity and malformed values", async () => {
  const handler = createAccountTransferHandler({
    loadEnv: env,
    authenticate: mockAuth([]),
  });
  assertEquals(
    (await handler(
      request({ ...draftBody("create"), p_verified_owner_auth_subject: actor }),
    )).status,
    422,
  );
  assertEquals(
    (await handler(request({ ...draftBody("create"), amount: 123.45 }))).status,
    422,
  );
  assertEquals(
    (await handler(
      request({
        ...draftBody("create"),
        source_account_id: destinationId,
        ledger_entries: [],
      }),
    )).status,
    422,
  );
  assertEquals(
    (await handler(
      request({
        action: "submit",
        financial_event_id: eventId,
        expected_version_number: 0,
      }),
    )).status,
    422,
  );
});

Deno.test("account transfer maps DB authorization and validation safely", async () => {
  const handler = createAccountTransferHandler({
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
                message: "Account transfer requires different Owner approval.",
              },
            }),
        },
      } as unknown as AuthenticatedContext),
  });
  const response = await handler(
    request({
      action: "approve",
      financial_event_id: eventId,
      expected_version_number: 3,
    }),
  );
  const json = await response.json();
  assertEquals(response.status, 401);
  assertEquals(String(json.error).includes("different Owner"), false);
});

Deno.test("account transfer responses are sanitized to allowlisted fields", async () => {
  const handler = createAccountTransferHandler({
    loadEnv: env,
    authenticate: mockAuth([]),
  });
  const response = await handler(
    request({ action: "detail", financial_event_id: eventId }),
  );
  const json = await response.json();
  assert(String(JSON.stringify(json)).includes("ledger_entry_id") === false);
  assert(String(JSON.stringify(json)).includes("service_role") === false);
});

function draftBody(action: string) {
  return {
    action,
    source_account_id: sourceId,
    destination_account_id: destinationId,
    amount: "123.45",
    currency_code: "USD",
    transfer_date: "2026-08-15",
    reference: "owner-ref-1",
    notes: "private",
  };
}
function summaryRow() {
  return {
    account_transfer_id: transferId,
    financial_event_id: eventId,
    event_number: "FE-000011",
    financial_transaction_id: txId,
    transaction_number: "FT-000011",
    source_account_id: sourceId,
    destination_account_id: destinationId,
    amount: "123.45",
    currency_code: "USD",
    transfer_date: "2026-08-15",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    version_number: 2,
  };
}
function detailRow() {
  return {
    ...summaryRow(),
    reference: "owner-ref-1",
    notes: "private",
    reporting_currency_code: "USD",
    submitted_at: "2026-08-15T00:00:00Z",
    approved_at: null,
    rejected_at: null,
    rejection_reason: null,
  };
}
function mutationRow() {
  return {
    financial_event_id: eventId,
    financial_transaction_id: txId,
    account_transfer_id: transferId,
    event_number: "FE-000011",
    transaction_number: "FT-000011",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    ledger_entry_count: 2,
    version_number: 3,
  };
}
