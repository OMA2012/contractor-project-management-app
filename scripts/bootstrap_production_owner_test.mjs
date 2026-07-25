import {
  activationRedirect,
  bootstrapProductionOwner,
  byteaHex,
  EXIT,
  generateTokenBytes,
  loadConfig,
  normalizeEmail,
  sha256,
  validateBaseUrl,
} from "./bootstrap_production_owner.mjs";

function assert(condition, message = "assertion failed") {
  if (!condition) throw new Error(message);
}

function assertEquals(actual, expected, message) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const baseEnv = {
  SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_SERVICE_ROLE_KEY: "service-secret-value",
  APP_BASE_URL: "http://localhost:3000",
  BOOTSTRAP_OWNER_EMAIL: " OWNER@Example.TEST ",
  BOOTSTRAP_OWNER_FULL_NAME: " Owner Name ",
  BOOTSTRAP_CONFIRMATION: "CREATE FIRST CONTRACTOR OWNER",
};

function mockClient(options = {}) {
  const calls = [];
  const row = {
    owner_user_id: "10000000-0000-4000-8000-000000000001",
    auth_subject: "00000000-0000-4000-8000-000000000001",
    normalized_email: "owner@example.test",
    account_status: "INVITED",
    is_active: false,
    invitation_id: "20000000-0000-4000-8000-000000000001",
    invitation_status: "PENDING",
    expires_at: "2026-08-01T00:00:00Z",
  };
  const client = {
    calls,
    auth: {
      admin: {
        generateLink: (args) => {
          calls.push(["generateLink", args]);
          return Promise.resolve(
            options.generateLink ??
              { data: { user: { id: row.auth_subject } }, error: null },
          );
        },
        inviteUserByEmail: (email, args) => {
          calls.push(["inviteUserByEmail", email, args]);
          return Promise.resolve(options.invite ?? { data: {}, error: null });
        },
      },
    },
    rpc: (name, args) => {
      calls.push(["rpc", name, args]);
      if (name === "server_bootstrap_first_owner") {
        return Promise.resolve(
          options.bootstrap ?? { data: [row], error: null },
        );
      }
      if (name === "server_first_owner_delivery_context") {
        return Promise.resolve(
          options.recovery ?? { data: [row], error: null },
        );
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return client;
}

function clientFactory(client) {
  return () => client;
}

Deno.test("validates missing environment and exact confirmation", () => {
  assertEquals(loadConfig(baseEnv).email, "owner@example.test");
  assertThrows(() => loadConfig({ ...baseEnv, SUPABASE_URL: "" }));
  assertThrows(() => loadConfig({ ...baseEnv, BOOTSTRAP_CONFIRMATION: "yes" }));
});

Deno.test("normalizes email, validates full name, base URL, localhost exception, and trusted route", () => {
  assertEquals(normalizeEmail(" A@Example.TEST "), "a@example.test");
  assertThrows(() =>
    loadConfig({ ...baseEnv, BOOTSTRAP_OWNER_FULL_NAME: "  " })
  );
  assertThrows(() => validateBaseUrl("http://example.test"));
  assertEquals(
    validateBaseUrl("http://localhost:3000/"),
    "http://localhost:3000",
  );
  assertEquals(
    activationRedirect("http://localhost:3000"),
    "http://localhost:3000/owner/activate",
  );
});

Deno.test("generates 32 bytes and SHA-256 digest suitable for bytea", async () => {
  const token = generateTokenBytes((bytes) => bytes.fill(7));
  assertEquals(token.length, 32);
  const digest = await sha256(token);
  assertEquals(digest.length, 32);
  assert(byteaHex(digest).startsWith("\\x"));
  assertEquals(byteaHex(digest).length, 66);
});

Deno.test("orders generateLink then bootstrap RPC then inviteUserByEmail", async () => {
  const client = mockClient();
  const result = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(client),
    random: (b) => b.fill(1),
  });
  assertEquals(result.exitCode, EXIT.ok);
  assertEquals(
    client.calls.map((call) => call[0] === "rpc" ? call[1] : call[0]),
    [
      "generateLink",
      "server_bootstrap_first_owner",
      "inviteUserByEmail",
    ],
  );
});

Deno.test("does not send email when bootstrap fails and recovery is not proven", async () => {
  const client = mockClient({
    bootstrap: { data: null, error: { code: "42501" } },
    recovery: { data: [], error: null },
  });
  const result = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(client),
  });
  assertEquals(result.exitCode, EXIT.recoveryNotProven);
  assertEquals(
    client.calls.some((call) => call[0] === "inviteUserByEmail"),
    false,
  );
});

Deno.test("permits delivery after same-identity recovery is proven", async () => {
  const client = mockClient({
    bootstrap: { data: null, error: { code: "42501" } },
  });
  const result = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(client),
  });
  assertEquals(result.exitCode, EXIT.ok);
  assertEquals(
    client.calls.map((call) => call[0] === "rpc" ? call[1] : call[0]),
    [
      "generateLink",
      "server_bootstrap_first_owner",
      "server_first_owner_delivery_context",
      "inviteUserByEmail",
    ],
  );
});

Deno.test("uses one delivery attempt and returns code 4 on delivery failure", async () => {
  const client = mockClient({
    invite: { data: null, error: { code: "timeout", message: "maybe sent" } },
  });
  const result = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(client),
  });
  assertEquals(result.exitCode, EXIT.deliveryUnconfirmed);
  assertEquals(
    client.calls.filter((call) => call[0] === "inviteUserByEmail").length,
    1,
  );
});

Deno.test("maps expired recovery to exit code 5", async () => {
  const client = mockClient({
    bootstrap: { data: null, error: { code: "42501" } },
    recovery: {
      data: null,
      error: { code: "P0001", message: "First Owner invitation expired." },
    },
  });
  const result = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(client),
  });
  assertEquals(result.exitCode, EXIT.expiredInvitation);
});

Deno.test("maps Auth preparation failure and invalid Auth response safely", async () => {
  const failed = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(
      mockClient({ generateLink: { data: null, error: { code: "auth" } } }),
    ),
  });
  assertEquals(failed.exitCode, EXIT.authPreparation);
  const invalid = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(
      mockClient({ generateLink: { data: { user: {} }, error: null } }),
    ),
  });
  assertEquals(invalid.exitCode, EXIT.authPreparation);
});

Deno.test("safe output leaks no service key, token, digest, OTP, or full activation link", async () => {
  const client = mockClient();
  const result = await bootstrapProductionOwner({
    env: baseEnv,
    clientFactory: clientFactory(client),
    random: (b) => b.fill(9),
  });
  const text = result.lines.join("\n");
  for (
    const forbidden of [
      "service-secret-value",
      "\\x",
      "otp",
      "token=",
      "/owner/activate",
      "OWNER@Example.TEST",
    ]
  ) {
    assert(!text.includes(forbidden), `leaked ${forbidden}`);
  }
  assert(text.includes("ow***@example.test"));
});

function assertThrows(fn) {
  let threw = false;
  try {
    fn();
  } catch {
    threw = true;
  }
  assert(threw, "expected function to throw");
}
