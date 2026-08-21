import { createHandler, type MalwareScanner, type ScanResult } from "./main.ts";

const TOKEN = "scanner-test-token";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function scanner(result: ScanResult | Error): MalwareScanner {
  return {
    ready: () => Promise.resolve(!(result instanceof Error)),
    scan: () =>
      result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result),
  };
}

function request(
  method = "POST",
  headers: Record<string, string> = {},
  body: BodyInit | null = new Uint8Array([1, 2, 3]),
): Request {
  return new Request("http://scanner.test/scan", { method, headers, body });
}

Deno.test("scan rejects a missing or malformed Authorization header", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
  });
  for (
    const authorization of [undefined, "Basic abc", "Bearer", "bearer token"]
  ) {
    const headers: Record<string, string> = {
      "content-type": "application/octet-stream",
    };
    if (authorization) headers.authorization = authorization;
    const response = await handler(request("POST", headers));
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { result: "ERROR" });
  }
});

Deno.test("scan rejects an incorrect bearer token", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
  });
  const response = await handler(request("POST", {
    authorization: "Bearer incorrect",
    "content-type": "application/octet-stream",
  }));
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { result: "ERROR" });
});

Deno.test("scan rejects unsupported methods", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
  });
  const response = await handler(request("GET", {}, null));
  assertEquals(response.status, 405);
  assertEquals(await response.json(), { result: "ERROR" });
});

Deno.test("scan requires application/octet-stream", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
  });
  const response = await handler(request("POST", {
    authorization: `Bearer ${TOKEN}`,
    "content-type": "application/pdf",
  }));
  assertEquals(response.status, 415);
  assertEquals(await response.json(), { result: "ERROR" });
});

Deno.test("scan maps a clean result to the client contract", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
  });
  const response = await handler(request("POST", {
    authorization: `Bearer ${TOKEN}`,
    "content-type": "application/octet-stream",
  }));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { result: "CLEAN" });
});

Deno.test("scan maps a malicious result to the client contract", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({
      result: "MALICIOUS",
      malware_name: "Eicar-Test-Signature",
    }),
  });
  const response = await handler(request("POST", {
    authorization: `Bearer ${TOKEN}`,
    "content-type": "application/octet-stream",
  }));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    result: "MALICIOUS",
    malware_name: "Eicar-Test-Signature",
  });
});

Deno.test("scanner failures return the explicit fail-closed ERROR contract", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner(new Error("unavailable")),
  });
  const response = await handler(request("POST", {
    authorization: `Bearer ${TOKEN}`,
    "content-type": "application/octet-stream",
  }));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { result: "ERROR" });
});

Deno.test("scan enforces its payload limit for streamed bodies", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
    maxDocumentBytes: 2,
  });
  const response = await handler(request("POST", {
    authorization: `Bearer ${TOKEN}`,
    "content-type": "application/octet-stream",
  }));
  assertEquals(response.status, 413);
  assertEquals(await response.json(), { result: "ERROR" });
});

Deno.test("health reports only ready state", async () => {
  const handler = createHandler({
    token: TOKEN,
    scanner: scanner({ result: "CLEAN" }),
  });
  const response = await handler(new Request("http://scanner.test/health"));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { status: "ready" });
});
