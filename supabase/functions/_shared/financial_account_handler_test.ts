import type { AuthenticatedContext } from "./auth.ts";
import type { AppEnv } from "./env.ts";
import { unauthorized } from "./errors.ts";
import { createFinancialAccountHandler } from "./financial_account_handler.ts";

const origin = "http://localhost:3000";
const actor = "00000000-0000-4000-8000-000000000001";
const accountId = "10000000-0000-4000-8000-000000000001";

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

function request(body: unknown, init: RequestInit = {}): Request {
  return new Request("http://127.0.0.1:54321/functions/v1/financial-accounts", {
    method: "POST",
    headers: {
      Origin: origin,
      "content-type": "application/json",
      authorization: "Bearer verified",
      ...init.headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function mockAuth(options: {
  calls: string[];
  rpcArgs?: Record<string, unknown>[];
  rpcErrors?: Record<string, { code?: string; message?: string }>;
}) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> => {
    options.calls.push("authenticate");
    const serviceClient = {
      rpc: (name: string, args: Record<string, unknown>) => {
        options.calls.push(`rpc:${name}`);
        options.rpcArgs?.push({ name, ...args });
        const error = options.rpcErrors?.[name] ?? null;
        if (error) return Promise.resolve({ data: null, error });
        if (name === "server_owner_financial_account_list") {
          return Promise.resolve({
            data: [safeAccount({ encrypted_account_details: "\\xsecret" })],
            error: null,
          });
        }
        if (name === "server_owner_financial_account_detail") {
          return Promise.resolve({
            data: [safeDetail({ ciphertext: "secret" })],
            error: null,
          });
        }
        if (name === "server_owner_financial_account_balance") {
          return Promise.resolve({
            data: [{
              financial_account_id: accountId,
              account_number: "FA-000001",
              account_type: "BANK",
              currency_code: "USD",
              balance: "12345678901234567890.1234",
            }],
            error: null,
          });
        }
        if (name.endsWith("_by_currency")) {
          return Promise.resolve({
            data: [
              { currency_code: "SAR", balance: "2.20" },
              { currency_code: "USD", balance: "1.10" },
              { currency_code: "YER", balance: "3.30" },
            ],
            error: null,
          });
        }
        if (name === "server_owner_create_financial_account") {
          return Promise.resolve({
            data: [{
              financial_account_id: accountId,
              account_number: "FA-000001",
              version_number: 1,
            }],
            error: null,
          });
        }
        if (name === "server_owner_update_financial_account_metadata") {
          return Promise.resolve({
            data: [{
              financial_account_id: accountId,
              account_number: "FA-000001",
              version_number: 2,
            }],
            error: null,
          });
        }
        if (
          name === "server_owner_activate_financial_account" ||
          name === "server_owner_deactivate_financial_account"
        ) {
          return Promise.resolve({
            data: [{
              financial_account_id: accountId,
              is_active: name.includes("activate"),
              version_number: 2,
            }],
            error: null,
          });
        }
        if (name === "server_owner_archive_financial_account") {
          return Promise.resolve({
            data: [{
              financial_account_id: accountId,
              is_active: false,
              archived_at: "2026-08-15T00:00:00Z",
              archived_by: actor,
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

function safeAccount(extra: Record<string, unknown> = {}) {
  return {
    id: accountId,
    account_number: "FA-000001",
    name: "Main cash",
    account_type: "CASH",
    currency_code: "USD",
    bank_name: null,
    masked_account_identifier: null,
    is_active: true,
    archived_at: null,
    version_number: 1,
    ...extra,
  };
}

function safeDetail(extra: Record<string, unknown> = {}) {
  return {
    ...safeAccount({
      name: "Main bank",
      account_type: "BANK",
      bank_name: "Bank",
      masked_account_identifier: "****1234",
    }),
    notes: "owner note",
    archived_by: null,
    created_at: "2026-08-15T00:00:00Z",
    created_by: actor,
    updated_at: "2026-08-15T00:00:00Z",
    updated_by: actor,
    ...extra,
  };
}

Deno.test("financial accounts rejects bad origin before auth and supports OPTIONS", async () => {
  const calls: string[] = [];
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const denied = await handler(
    request({ action: "list" }, {
      headers: { Origin: "https://blocked.example" },
    }),
  );
  assertEquals(denied.status, 403);
  assertEquals(calls, []);
  const options = await handler(
    new Request("http://local", {
      method: "OPTIONS",
      headers: { Origin: origin },
    }),
  );
  assertEquals(options.status, 204);
  assertEquals(options.headers.get("Access-Control-Allow-Origin"), origin);
});

Deno.test("financial accounts maps unauthenticated request and unsupported method safely", async () => {
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: () => {
      throw unauthorized();
    },
  });
  assertEquals((await handler(request({ action: "list" }))).status, 401);
  assertEquals(
    (await handler(
      new Request("http://local", {
        method: "GET",
        headers: { Origin: origin },
      }),
    )).status,
    405,
  );
});

Deno.test("financial accounts rejects malformed JSON, unknown action, and spoofed owner fields", async () => {
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [] }),
  });
  assertEquals((await handler(request("{"))).status, 400);
  assertEquals((await handler(request({ action: "payment" }))).status, 422);
  assertEquals(
    (await handler(request({ action: "list", owner_id: actor }))).status,
    422,
  );
  assertEquals(
    (await handler(
      request({
        action: "detail",
        financial_account_id: accountId,
        verified_owner_auth_subject: actor,
      }),
    )).status,
    422,
  );
});

Deno.test("list calls exact RPC with derived actor and sanitizes private fields", async () => {
  const calls: string[] = [];
  const rpcArgs: Record<string, unknown>[] = [];
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls, rpcArgs }),
  });
  const response = await handler(
    request({ action: "list", include_archived: true, limit: 25, offset: 5 }),
  );
  const text = await response.text();
  assertEquals(response.status, 200);
  assertEquals(rpcArgs[0].name, "server_owner_financial_account_list");
  assertEquals(rpcArgs[0].p_verified_owner_auth_subject, actor);
  assertEquals(rpcArgs[0].p_limit, 25);
  assert(!text.includes("encrypted_account_details"));
  assert(!text.includes("service-role-placeholder"));
});

Deno.test("detail returns allowlisted owner/admin safe metadata only", async () => {
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [] }),
  });
  const response = await handler(
    request({ action: "detail", financial_account_id: accountId }),
  );
  const text = await response.text();
  const body = JSON.parse(text);
  assertEquals(body.data.account.masked_account_identifier, "****1234");
  assert(!text.includes("ciphertext"));
});

Deno.test("balance and totals preserve exact decimal strings and separate currencies", async () => {
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [] }),
  });
  const balance = await (await handler(
    request({ action: "balance", financial_account_id: accountId }),
  )).json();
  assertEquals(balance.data.balance.balance, "12345678901234567890.1234");
  const totals =
    await (await handler(request({ action: "cash_totals_by_currency" })))
      .json();
  assertEquals(
    totals.data.totals.map((row: Record<string, unknown>) => row.currency_code),
    ["SAR", "USD", "YER"],
  );
  assertEquals(totals.data.grand_total, undefined);
});

Deno.test("balances by currency calls exact RPC and preserves exact separate rows", async () => {
  const rpcArgs: Record<string, unknown>[] = [];
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [], rpcArgs }),
  });
  const response = await handler(request({ action: "balances_by_currency" }));
  const text = await response.text();
  const body = JSON.parse(text);
  assertEquals(response.status, 200);
  assertEquals(
    rpcArgs[0].name,
    "server_owner_financial_account_balances_by_currency",
  );
  assertEquals(rpcArgs[0].p_verified_owner_auth_subject, actor);
  assertEquals(body.data.balances, [
    { currency_code: "SAR", balance: "2.20" },
    { currency_code: "USD", balance: "1.10" },
    { currency_code: "YER", balance: "3.30" },
  ]);
  assertEquals(body.data.total, undefined);
  assert(!text.includes("encrypted_account_details"));
});

Deno.test("bank totals by currency calls exact RPC and preserves exact separate totals", async () => {
  const rpcArgs: Record<string, unknown>[] = [];
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [], rpcArgs }),
  });
  const response = await handler(
    request({ action: "bank_totals_by_currency" }),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(rpcArgs[0].name, "server_owner_bank_totals_by_currency");
  assertEquals(rpcArgs[0].p_verified_owner_auth_subject, actor);
  assertEquals(body.data.totals, [
    { currency_code: "SAR", balance: "2.20" },
    { currency_code: "USD", balance: "1.10" },
    { currency_code: "YER", balance: "3.30" },
  ]);
  assertEquals(body.data.grand_total, undefined);
});

Deno.test("create passes null encrypted details and derived owner subject", async () => {
  const rpcArgs: Record<string, unknown>[] = [];
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [], rpcArgs }),
  });
  const response = await handler(
    request({
      action: "create",
      name: "Cash",
      account_type: "CASH",
      currency_code: "USD",
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(rpcArgs[0].name, "server_owner_create_financial_account");
  assertEquals(rpcArgs[0].p_verified_owner_auth_subject, actor);
  assertEquals(rpcArgs[0].p_encrypted_account_details, null);
});

Deno.test("update calls safe metadata RPC and rejects private financial fields", async () => {
  const rpcArgs: Record<string, unknown>[] = [];
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [], rpcArgs }),
  });
  const response = await handler(
    request({
      action: "update",
      financial_account_id: accountId,
      expected_version_number: 1,
      name: "Bank",
      account_type: "BANK",
      currency_code: "USD",
      bank_name: "Safe Bank",
      masked_account_identifier: "****1234",
      notes: "safe note",
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(
    rpcArgs[0].name,
    "server_owner_update_financial_account_metadata",
  );
  assertEquals(rpcArgs[0].p_verified_owner_auth_subject, actor);
  assertEquals(rpcArgs[0].p_encrypted_account_details, undefined);

  for (
    const field of [
      "encrypted_account_details",
      "plaintext_bank_secret",
      "ciphertext",
      "balance",
      "opening_balance",
      "account_number",
      "created_by",
      "owner_auth_subject",
    ]
  ) {
    const rejected = await handler(request({
      action: "update",
      financial_account_id: accountId,
      expected_version_number: 1,
      name: "Bank",
      account_type: "BANK",
      currency_code: "USD",
      bank_name: "Safe Bank",
      masked_account_identifier: "****1234",
      [field]: "not allowed",
    }));
    assertEquals(rejected.status, 422);
  }
});

Deno.test("activate deactivate and archive call exact lifecycle RPC payloads", async () => {
  for (const action of ["activate", "deactivate", "archive"]) {
    const rpcArgs: Record<string, unknown>[] = [];
    const handler = createFinancialAccountHandler({
      loadEnv: env,
      authenticate: mockAuth({ calls: [], rpcArgs }),
    });
    const response = await handler(
      request({
        action,
        financial_account_id: accountId,
        expected_version_number: 1,
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(rpcArgs[0].name, `server_owner_${action}_financial_account`);
    assertEquals(rpcArgs[0].p_verified_owner_auth_subject, actor);
    assertEquals(rpcArgs[0].p_expected_version_number, 1);
  }
});

Deno.test("database authorization and posted history failures map to safe responses", async () => {
  const denied = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({
      calls: [],
      rpcErrors: {
        server_owner_financial_account_list: {
          code: "42501",
          message: "Privileged operation denied.",
        },
      },
    }),
  });
  assertEquals((await denied(request({ action: "list" }))).status, 401);
  const conflict = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({
      calls: [],
      rpcErrors: {
        server_owner_create_financial_account: {
          code: "23514",
          message:
            "Financial account type and currency are immutable after posted financial history.",
        },
      },
    }),
  });
  const response = await conflict(
    request({
      action: "create",
      name: "Cash",
      account_type: "CASH",
      currency_code: "USD",
    }),
  );
  const text = await response.text();
  assertEquals(response.status, 422);
  assert(!text.includes("posted financial history"));
});

Deno.test("identifier and input validation rejects malformed values", async () => {
  const handler = createFinancialAccountHandler({
    loadEnv: env,
    authenticate: mockAuth({ calls: [] }),
  });
  for (
    const body of [
      { action: "detail" },
      { action: "detail", financial_account_id: "bad" },
      { action: "list", limit: 101 },
      { action: "list", offset: -1 },
      {
        action: "create",
        name: "Cash",
        account_type: "SAFE",
        currency_code: "USD",
      },
      {
        action: "create",
        name: "Cash",
        account_type: "CASH",
        currency_code: "US",
      },
      {
        action: "activate",
        financial_account_id: accountId,
        expected_version_number: 0,
      },
    ]
  ) {
    assertEquals((await handler(request(body))).status, 422);
  }
});
