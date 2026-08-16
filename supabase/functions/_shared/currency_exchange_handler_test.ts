import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { createCurrencyExchangeHandler } from "./currency_exchange_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000011";
const eventId = "10000000-0000-4000-8000-000000000011";
const txId = "20000000-0000-4000-8000-000000000011";
const exchangeId = "30000000-0000-4000-8000-000000000011";
const sourceId = "40000000-0000-4000-8000-000000000011";
const destinationId = "50000000-0000-4000-8000-000000000011";
const rateId = "60000000-0000-4000-8000-000000000011";

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
  return new Request("http://127.0.0.1:54321/functions/v1/currency-exchanges", {
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
          if (name === "server_owner_currency_exchange_list") {
            return Promise.resolve({ data: [summaryRow()], error: null });
          }
          if (name === "server_owner_currency_exchange_detail") {
            return Promise.resolve({ data: [detailRow()], error: null });
          }
          return Promise.resolve({ data: [mutationRow()], error: null });
        },
      },
    } as unknown as AuthenticatedContext);
}

Deno.test("currency exchange gateway handles authenticated Owner list and detail", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createCurrencyExchangeHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  let response = await handler(request({ action: "list" }));
  let json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_currency_exchange_list");
  assertEquals(calls[0].p_verified_owner_auth_subject, actor);
  assertEquals(json.data.currency_exchanges[0].source_amount, "12500.00");

  response = await handler(
    request({ action: "detail", financial_event_id: eventId }),
  );
  json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[1].name, "server_owner_currency_exchange_detail");
  assertEquals(json.data.currency_exchange.rate_value, "0.264600");
});

Deno.test("currency exchange create and update preserve exact decimal and rate strings", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createCurrencyExchangeHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
  });
  const response = await handler(request(draftBody("create")));
  const json = await response.json();
  assertEquals(response.status, 200);
  assertEquals(calls[0].name, "server_owner_create_currency_exchange");
  assertEquals(calls[0].p_source_amount, "12500.0000");
  assertEquals(calls[0].p_exchange_rate_id, rateId);
  assertEquals(json.data.currency_exchange.destination_amount, "3307.500000");

  await handler(
    request({
      ...draftBody("update"),
      financial_event_id: eventId,
      expected_version_number: 2,
    }),
  );
  assertEquals(calls[1].name, "server_owner_update_currency_exchange");
  assertEquals(calls[1].p_expected_version_number, 2);
});

Deno.test("currency exchange submit approve and reject use workflow RPCs", async () => {
  const calls: Record<string, unknown>[] = [];
  const handler = createCurrencyExchangeHandler({
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
    "server_owner_submit_currency_exchange",
    "server_owner_approve_currency_exchange",
    "server_owner_reject_currency_exchange",
  ]);
});

Deno.test("currency exchange rejects spoofed identity, unknown fields, and malformed values", async () => {
  const handler = createCurrencyExchangeHandler({
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
    (await handler(request({ ...draftBody("create"), source_amount: 12500 })))
      .status,
    422,
  );
  assertEquals(
    (await handler(request({ ...draftBody("create"), ledger_entries: [] })))
      .status,
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

Deno.test("currency exchange maps DB authorization safely and sanitizes responses", async () => {
  const denied = createCurrencyExchangeHandler({
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
                message: "requires different Owner approval",
              },
            }),
        },
      } as unknown as AuthenticatedContext),
  });
  const deniedResponse = await denied(
    request({
      action: "approve",
      financial_event_id: eventId,
      expected_version_number: 3,
    }),
  );
  const deniedJson = await deniedResponse.json();
  assertEquals(deniedResponse.status, 401);
  assertEquals(String(deniedJson.error).includes("different Owner"), false);

  const handler = createCurrencyExchangeHandler({
    loadEnv: env,
    authenticate: mockAuth([]),
  });
  const response = await handler(
    request({ action: "detail", financial_event_id: eventId }),
  );
  const json = await response.json();
  assert(String(JSON.stringify(json)).includes("ledger_entry_id") === false);
  assert(String(JSON.stringify(json)).includes("CTRL-FX") === false);
  assert(String(JSON.stringify(json)).includes("service_role") === false);
});

function draftBody(action: string) {
  return {
    action,
    source_account_id: sourceId,
    destination_account_id: destinationId,
    source_amount: "12500.0000",
    exchange_rate_id: rateId,
    fee_amount: "0",
    exchange_date: "2026-08-15",
    reference: "owner-ref-1",
  };
}
function summaryRow() {
  return {
    currency_exchange_id: exchangeId,
    financial_event_id: eventId,
    event_number: "FE-000011",
    financial_transaction_id: txId,
    transaction_number: "FT-000011",
    project_id: null,
    client_id: null,
    source_account_id: sourceId,
    destination_account_id: destinationId,
    source_amount: "12500.00",
    source_currency_code: "SAR",
    destination_amount: "3307.50",
    destination_currency_code: "USD",
    fee_amount: "0",
    fee_currency_code: null,
    exchange_date: "2026-08-15",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    version_number: 2,
  };
}
function detailRow() {
  return {
    ...summaryRow(),
    exchange_rate_id: rateId,
    rate_base_currency_code: "SAR",
    rate_quote_currency_code: "USD",
    rate_value: "0.264600",
    rate_source: "MANUAL",
    fee_account_id: null,
    rounding_result: "0.000000",
    reference: "OWNER-REF-1",
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
    currency_exchange_id: exchangeId,
    event_number: "FE-000011",
    transaction_number: "FT-000011",
    destination_amount: "3307.500000",
    rounding_result: "0.000000",
    event_status: "SUBMITTED",
    transaction_status: "SUBMITTED",
    ledger_entry_count: 4,
    version_number: 3,
  };
}
