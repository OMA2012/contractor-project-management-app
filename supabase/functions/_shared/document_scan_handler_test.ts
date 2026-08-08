import type { AppEnv } from "./env.ts";
import type { AuthenticatedContext } from "./auth.ts";
import {
  createDocumentScanHandler,
  createHttpsScannerAdapter,
} from "./document_scan_handler.ts";

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
        `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const actor = "00000000-0000-4000-8000-000000000001";
const uploadId = "10000000-0000-4000-8000-000000000001";
const scanId = "30000000-0000-4000-8000-000000000001";
const documentId = "20000000-0000-4000-8000-000000000001";
const tempKey =
  `temporary/${uploadId}/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;
const finalKey =
  `objects/${documentId}/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB`;
const origin = "http://localhost:3000";
const pdfBytes = new TextEncoder().encode("%PDF-123");
const pdfHash =
  "\\x4e2ecf61e23632905078b35e3b595dfee8f5032cf90016a5140cafee2decf4c3";

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

function request(body: Record<string, unknown>): Request {
  return new Request(
    "http://127.0.0.1:54321/functions/v1/document-scan-finalize",
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

function mockAuth(
  calls: string[],
  options: {
    rpcError?: { code?: string };
    badHash?: boolean;
    resumeFinalizing?: boolean;
    existingFinalBytes?: Uint8Array;
  } = {},
) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> => {
    let cleanScanRecorded = options.resumeFinalizing ?? false;
    let finalUploaded = false;
    const serviceClient = {
      rpc: (name: string, args: Record<string, unknown>) => {
        calls.push(`rpc:${name}`);
        assert(!JSON.stringify(args).includes("DOCUMENT_SCANNER_TOKEN"));
        if (options.rpcError) {
          return Promise.resolve({ data: null, error: options.rpcError });
        }
        if (name === "server_owner_record_document_scan_result") {
          cleanScanRecorded = args.p_result === "CLEAN";
          return Promise.resolve({
            data: [{ upload_id: uploadId, status: "SCAN_CLEAN" }],
            error: null,
          });
        }
        if (name === "server_owner_start_document_scan") {
          return Promise.resolve({
            data: [{
              scan_id: scanId,
              upload_id: uploadId,
              attempt_number: 1,
              storage_bucket: "documents-private",
              storage_object_key: tempKey,
              verified_file_size_bytes: pdfBytes.byteLength,
              verified_sha256_hash: options.badHash
                ? "\\xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                : pdfHash,
            }],
            error: null,
          });
        }
        if (name === "server_owner_prepare_clean_document_finalization") {
          if (!cleanScanRecorded) {
            return Promise.resolve({
              data: null,
              error: { code: "23514" },
            });
          }
          return Promise.resolve({
            data: [{
              upload_id: uploadId,
              reserved_document_id: documentId,
              storage_bucket: "documents-private",
              temporary_storage_object_key: tempKey,
              final_storage_object_key: finalKey,
              verified_file_size_bytes: pdfBytes.byteLength,
              verified_sha256_hash: pdfHash,
              verified_mime_type: "application/pdf",
            }],
            error: null,
          });
        }
        if (name === "server_owner_finalize_clean_document_upload") {
          return Promise.resolve({
            data: [{
              document_id: documentId,
              document_number: "DOC-000001",
              storage_object_key: finalKey,
              status: "FINALIZED",
            }],
            error: null,
          });
        }
        return Promise.resolve({
          data: [{ upload_id: uploadId, status: "SCAN_CLEAN" }],
          error: null,
        });
      },
      storage: {
        from: (bucket: string) => {
          calls.push(`storage:${bucket}`);
          return {
            download: (path: string) => {
              calls.push(`download:${path}`);
              if (path === finalKey && !finalUploaded) {
                if (options.existingFinalBytes) {
                  return Promise.resolve({
                    data: new Blob([arrayBufferOf(options.existingFinalBytes)]),
                    error: null,
                  });
                }
                return Promise.resolve({
                  data: null,
                  error: { code: "404" },
                });
              }
              return Promise.resolve({
                data: new Blob([pdfBytes]),
                error: null,
              });
            },
            upload: (
              path: string,
              _body: Blob,
              options: { contentType: string; upsert: boolean },
            ) => {
              calls.push(
                `upload:${path}:${options.contentType}:${options.upsert}`,
              );
              finalUploaded = path === finalKey;
              return Promise.resolve({ data: {}, error: null });
            },
          };
        },
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

function arrayBufferOf(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

Deno.test("document scan finalizes only after clean scanner result", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
    scanner: {
      scan: () => Promise.resolve({ verdict: "CLEAN", scanner_version: "1.0" }),
    },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.status, "FINALIZED");
  assert(calls.includes("rpc:server_owner_record_document_scan_result"));
  assert(calls.some((call) => call.startsWith("upload:objects/")));
  assert(!JSON.stringify(body).includes("temporary/"));
});

Deno.test("document scan resumes finalizing upload without creating another scan", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls, { resumeFinalizing: true }),
    scanner: {
      scan: () => {
        throw new Error("scanner should not be called");
      },
    },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.status, "FINALIZED");
  assert(!calls.includes("rpc:server_owner_start_document_scan"));
  assert(!calls.includes("rpc:server_owner_record_document_scan_result"));
  assert(calls.some((call) => call.startsWith("upload:objects/")));
});

Deno.test("document scan accepts already-present verified final object", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls, {
      resumeFinalizing: true,
      existingFinalBytes: pdfBytes,
    }),
    scanner: {
      scan: () => {
        throw new Error("scanner should not be called");
      },
    },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.status, "FINALIZED");
  assert(!calls.some((call) => call.startsWith("upload:")));
});

Deno.test("document scan fails closed on wrong existing final object", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls, {
      resumeFinalizing: true,
      existingFinalBytes: new TextEncoder().encode("%PDF-wrong"),
    }),
    scanner: { scan: () => Promise.resolve({ verdict: "CLEAN" }) },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 422);
  assert(!calls.some((call) => call.startsWith("upload:")));
});

Deno.test("document scan quarantines malicious result without final object", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
    scanner: {
      scan: () =>
        Promise.resolve({ verdict: "MALICIOUS", malware_name: "Eicar-Test" }),
    },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.status, "QUARANTINED");
  assert(!calls.some((call) => call.startsWith("upload:")));
});

Deno.test("document scan fails closed on scanner error and unknown result", async () => {
  for (
    const result of [{ verdict: "ERROR" as const }, {
      verdict: "ERROR" as const,
      failure_category: "unknown_result",
    }]
  ) {
    const calls: string[] = [];
    const handler = createDocumentScanHandler({
      loadEnv: env,
      authenticate: mockAuth(calls),
      scanner: { scan: () => Promise.resolve(result) },
    });
    const response = await handler(request({ upload_id: uploadId }));
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.data.status, "SCAN_FAILED");
    assert(!calls.some((call) => call.startsWith("upload:")));
  }
});

Deno.test("document scan fails closed on timeout or network error", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
    scanner: {
      scan: () => {
        throw new Error("network detail with DOCUMENT_SCANNER_TOKEN");
      },
    },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.status, "SCAN_FAILED");
  assert(!JSON.stringify(body).includes("DOCUMENT_SCANNER_TOKEN"));
});

Deno.test("document scan rejects caller-supplied scan facts", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls),
    scanner: { scan: () => Promise.resolve({ verdict: "CLEAN" }) },
  });
  const response = await handler(
    request({ upload_id: uploadId, result: "CLEAN" }),
  );
  assertEquals(response.status, 422);
  assertEquals(calls, []);
});

Deno.test("document scan records hash mismatch as failed closed", async () => {
  const calls: string[] = [];
  const handler = createDocumentScanHandler({
    loadEnv: env,
    authenticate: mockAuth(calls, { badHash: true }),
    scanner: { scan: () => Promise.resolve({ verdict: "CLEAN" }) },
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 422);
  assert(calls.includes("rpc:server_owner_record_document_scan_result"));
  assert(!calls.some((call) => call.startsWith("upload:")));
});

Deno.test("https scanner requires configured HTTPS endpoint and token", async () => {
  const bytes = new Uint8Array([1, 2, 3]);
  const signal = new AbortController().signal;
  assertEquals(
    await createHttpsScannerAdapter({}).scan(bytes, signal),
    { verdict: "ERROR", failure_category: "scanner_unavailable" },
  );
  assertEquals(
    await createHttpsScannerAdapter({
      DOCUMENT_SCANNER_URL: "http://scanner.example.test",
      DOCUMENT_SCANNER_TOKEN: "secret",
    }).scan(bytes, signal),
    { verdict: "ERROR", failure_category: "scanner_unavailable" },
  );
  assertEquals(
    await createHttpsScannerAdapter({
      DOCUMENT_SCANNER_URL: "not a url",
      DOCUMENT_SCANNER_TOKEN: "secret",
    }).scan(bytes, signal),
    { verdict: "ERROR", failure_category: "scanner_unavailable" },
  );
});

Deno.test("https scanner sends bearer token without following redirects", async () => {
  const calls: RequestInit[] = [];
  const scanner = createHttpsScannerAdapter(
    {
      DOCUMENT_SCANNER_URL: "https://scanner.example.test/scan",
      DOCUMENT_SCANNER_TOKEN: "scanner-secret",
    },
    (_url, init) => {
      calls.push(init);
      return Promise.resolve(
        new Response(JSON.stringify({ result: "CLEAN" }), { status: 200 }),
      );
    },
  );
  const result = await scanner.scan(
    new Uint8Array([1, 2, 3]),
    new AbortController().signal,
  );
  assertEquals(result.verdict, "CLEAN");
  assertEquals(calls[0].redirect, "manual");
  assertEquals(
    (calls[0].headers as Record<string, string>).Authorization,
    "Bearer scanner-secret",
  );
});

Deno.test("https scanner fails closed on malformed or oversized responses", async () => {
  const envVars = {
    DOCUMENT_SCANNER_URL: "https://scanner.example.test/scan",
    DOCUMENT_SCANNER_TOKEN: "scanner-secret",
  };
  const malformed = createHttpsScannerAdapter(
    envVars,
    () => Promise.resolve(new Response("{", { status: 200 })),
  );
  assertEquals(
    await malformed.scan(new Uint8Array([1]), new AbortController().signal),
    { verdict: "ERROR", failure_category: "network_error" },
  );
  const oversized = createHttpsScannerAdapter(
    envVars,
    () => Promise.resolve(new Response("x".repeat(8193), { status: 200 })),
  );
  assertEquals(
    await oversized.scan(new Uint8Array([1]), new AbortController().signal),
    { verdict: "ERROR", failure_category: "network_error" },
  );
});
