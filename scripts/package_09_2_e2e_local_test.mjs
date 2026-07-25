import {
  assertLocalSupabaseUrl,
  cleanupAll,
  EXIT,
  extractInviteParts,
  parseSupabaseStatus,
  redact,
  safeLine,
  startFunctionsServe,
  waitForMail,
  writeNoBomEnvFile,
} from "./package_09_2_e2e_local.mjs";

function assert(condition, message = "assertion failed") {
  if (!condition) throw new Error(message);
}

function assertEquals(actual, expected, message) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function assertRejects(fn, messageIncludes) {
  try {
    await fn();
  } catch (error) {
    if (
      messageIncludes && !String(error?.message ?? "").includes(messageIncludes)
    ) {
      throw new Error(`expected error including ${messageIncludes}`);
    }
    return error;
  }
  throw new Error("expected rejection");
}

Deno.test("local-only URL enforcement rejects hosted projects", async () => {
  assertEquals(
    assertLocalSupabaseUrl("http://127.0.0.1:54321/"),
    "http://127.0.0.1:54321",
  );
  assertEquals(
    assertLocalSupabaseUrl("http://localhost:54321"),
    "http://localhost:54321",
  );
  await assertRejects(
    () =>
      Promise.resolve(assertLocalSupabaseUrl("https://project.supabase.co")),
    "local Supabase",
  );
});

Deno.test("supabase status parsing requires safe local service values", async () => {
  const status = parseSupabaseStatus(`noise
{
  "API_URL": "http://127.0.0.1:54321",
  "MAILPIT_URL": "http://127.0.0.1:54324",
  "PUBLISHABLE_KEY": "publishable-placeholder",
  "SERVICE_ROLE_KEY": "service-placeholder"
}`);
  assertEquals(status.API_URL, "http://127.0.0.1:54321");
  assertEquals(status.FUNCTIONS_URL, "http://127.0.0.1:54321/functions/v1");
  await assertRejects(
    () =>
      Promise.resolve(
        parseSupabaseStatus(
          `{"API_URL":"https://hosted.supabase.co","FUNCTIONS_URL":"x","MAILPIT_URL":"x","PUBLISHABLE_KEY":"x","SERVICE_ROLE_KEY":"x"}`,
        ),
      ),
    "local Supabase",
  );
});

Deno.test("Mailpit polling extracts only invite verification values and times out safely", async () => {
  let calls = 0;
  const fetchImpl = (url) => {
    calls++;
    if (String(url).endsWith("/api/v1/messages")) {
      return new Response(JSON.stringify({
        messages: [{
          ID: "message-1",
          To: [{ Address: "client@example.test" }],
          Created: new Date().toISOString(),
        }],
      }));
    }
    return new Response(JSON.stringify({
      Text:
        "Open http://127.0.0.1:54321/auth/v1/verify?token=redacted-token-hash&type=invite&redirect_to=http%3A%2F%2Flocalhost%3A3000%2Faccept-invitation%3Ftoken%3Dredacted-app-token",
    }));
  };
  const message = await waitForMail({
    fetchImpl,
    mailpitUrl: "http://127.0.0.1:54324",
    email: "client@example.test",
    timeoutMs: 100,
  });
  const parts = extractInviteParts(message);
  assertEquals(parts.tokenHash, "redacted-token-hash");
  assertEquals(parts.appToken, "redacted-app-token");
  assertEquals(parts.safeVerifyRoute, "127.0.0.1:54321/auth/v1/verify");
  assertEquals(parts.safeRedirectRoute, "localhost:3000/accept-invitation");
  assert(calls >= 2);

  await assertRejects(
    () =>
      waitForMail({
        fetchImpl: () => new Response(JSON.stringify({ messages: [] })),
        mailpitUrl: "http://127.0.0.1:54324",
        email: "missing@example.test",
        timeoutMs: 1,
      }),
    "Timed out",
  );
});

Deno.test("recursive redaction removes tokens, JWTs, full links, and secret-like fields", () => {
  const output = JSON.stringify(redact({
    authorization: "Bearer eyJabc.secret",
    url: "http://localhost:3000/accept-invitation?token=secret-token-value",
    nested: {
      access_token: "access-token-value",
      safe: "ok",
    },
  }));
  assert(!output.includes("eyJabc"));
  assert(!output.includes("secret-token-value"));
  assert(!output.includes("access-token-value"));
  assert(output.includes("ok"));
  assert(
    !safeLine("link", "http://x.test/path?token=secret").includes("secret"),
  );
});

Deno.test("no-BOM env-file generation writes only APP_BASE_URL", async () => {
  let stored = new Uint8Array();
  await writeNoBomEnvFile("mock.env", {
    writeTextFile: (_path, value) => {
      stored = new TextEncoder().encode(value);
    },
    readFile: () => stored,
  });
  assert(!(stored[0] === 0xef && stored[1] === 0xbb && stored[2] === 0xbf));
  assertEquals(
    new TextDecoder().decode(stored),
    "APP_BASE_URL=http://localhost:3000\n",
  );
});

Deno.test("process startup/readiness and termination are dependency-injected", async () => {
  class MockCommand {
    constructor() {}
    spawn() {
      let killed = false;
      const encoder = new TextEncoder();
      const text = [
        "create-client-invitation",
        "resend-client-invitation",
        "revoke-client-invitation",
        "accept-client-invitation",
        "suspend-client-account",
        "reactivate-client-account",
        "disable-client-account",
      ].join("\n");
      return {
        stdout: new ReadableStream({
          start(controller) {
            controller.enqueue(encoder.encode(text));
            controller.close();
          },
        }),
        stderr: new ReadableStream({
          start(controller) {
            controller.close();
          },
        }),
        status: Promise.resolve({ success: true }),
        kill() {
          killed = true;
        },
        get killed() {
          return killed;
        },
      };
    }
  }
  const serve = await startFunctionsServe({
    cwd: ".",
    envFile: "temp.env",
    timeoutMs: 1000,
    commandFactory: MockCommand,
  });
  assert(String(serve.output()).includes("create-client-invitation"));
  await serve.stop();
});

Deno.test("cleanup executes after failure paths and maps cleanup errors", async () => {
  const lines = [];
  let stopped = false;
  await cleanupAll({
    status: null,
    serve: {
      stop: () => {
        stopped = true;
      },
    },
    envFile: null,
    root: ".",
    reset: false,
    lines,
  });
  assert(stopped);
  assert(lines.includes("cleanup=ok"));

  const error = await assertRejects(
    () =>
      cleanupAll({
        status: null,
        serve: {
          stop: () => {
            throw new Error("stop failed");
          },
        },
        envFile: "",
        root: ".",
        reset: false,
        lines: [],
      }),
    "Cleanup failed",
  );
  assertEquals(error.exitCode, EXIT.cleanup);
});
