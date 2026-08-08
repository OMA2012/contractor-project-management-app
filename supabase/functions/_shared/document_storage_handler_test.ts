import type { AppEnv } from "./env.ts";
import type { AuthenticatedContext } from "./auth.ts";
import { unauthorized } from "./errors.ts";
import { createDocumentStorageHandler } from "./document_storage_handler.ts";

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
const documentId = "20000000-0000-4000-8000-000000000001";
const origin = "http://localhost:3000";

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

function request(
  body: Record<string, unknown>,
  init: RequestInit = {},
): Request {
  return new Request("http://127.0.0.1:54321/functions/v1/document", {
    method: "POST",
    headers: {
      Origin: origin,
      "content-type": "application/json",
      authorization: "Bearer verified",
      ...init.headers,
    },
    body: JSON.stringify(body),
  });
}

function mockAuth(options: {
  calls: string[];
  rpcError?: { code?: string; message?: string };
  downloadText?: string;
}) {
  return (_req: Request, _env: AppEnv): Promise<AuthenticatedContext> => {
    options.calls.push("authenticate");
    const serviceClient = {
      rpc: (name: string) => {
        options.calls.push(`rpc:${name}`);
        if (options.rpcError) {
          return Promise.resolve({ data: null, error: options.rpcError });
        }
        if (name === "server_owner_reserve_document_upload") {
          return Promise.resolve({
            data: [{
              upload_id: uploadId,
              reserved_document_id: documentId,
              storage_bucket: "documents-private",
              storage_object_key:
                `temporary/${uploadId}/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`,
              expires_at: "2026-08-08T00:05:00Z",
            }],
            error: null,
          });
        }
        if (name === "server_owner_document_upload_storage_context") {
          return Promise.resolve({
            data: [{
              upload_id: uploadId,
              status: "AUTHORIZED",
              storage_bucket: "documents-private",
              storage_object_key:
                `temporary/${uploadId}/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`,
              expires_at: "2026-08-08T00:05:00Z",
            }],
            error: null,
          });
        }
        if (name === "server_owner_complete_document_upload") {
          return Promise.resolve({
            data: [{
              upload_id: uploadId,
              status: "AWAITING_SCAN",
              reserved_document_id: documentId,
              verified_mime_type: "application/pdf",
              verified_file_size_bytes: 8,
            }],
            error: null,
          });
        }
        if (name === "server_authorize_document_access") {
          return Promise.resolve({
            data: [{
              document_id: documentId,
              document_number: "DOC-000001",
              storage_bucket: "documents-private",
              storage_object_key: `objects/${documentId}/opaque`,
              original_file_name: "visible.pdf",
              mime_type: "application/pdf",
              file_size_bytes: 8,
              status: "ACTIVE",
              content_disposition: 'inline; filename="visible.pdf"',
            }],
            error: null,
          });
        }
        return Promise.resolve({ data: null, error: null });
      },
      storage: {
        from: (bucket: string) => {
          options.calls.push(`storage:${bucket}`);
          return {
            createSignedUploadUrl: (path: string) => {
              options.calls.push(`signed:${path}`);
              return Promise.resolve({
                data: {
                  signedUrl: "https://storage.example/upload-token",
                  token: "token",
                },
                error: null,
              });
            },
            download: (path: string) => {
              options.calls.push(`download:${path}`);
              return Promise.resolve({
                data: new Blob([options.downloadText ?? "%PDF-123"]),
                error: null,
              });
            },
            remove: (paths: string[]) => {
              options.calls.push(`remove:${paths.join(",")}`);
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

Deno.test("document upload authorization validates origin, file type, and returns only temporary upload facts", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-upload-authorize", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({
    original_file_name: "contract.pdf",
    mime_type: "application/pdf",
    document_type_code: "GENERAL",
    client_visible: true,
    client_id: "30000000-0000-4000-8000-000000000001",
  }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.upload_id, uploadId);
  assertEquals(body.data.max_file_size_bytes, 26214400);
  assert(!JSON.stringify(body).includes("service-role"));
  assert(!JSON.stringify(body).includes("objects/"));
  assert(calls.some((call) => call.startsWith("signed:temporary/")));
});

Deno.test("document upload authorization rejects dangerous double extensions before storage", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-upload-authorize", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({
    original_file_name: "invoice.pdf.exe",
    mime_type: "application/pdf",
    document_type_code: "GENERAL",
    client_id: "30000000-0000-4000-8000-000000000001",
  }));
  assertEquals(response.status, 422);
  assertEquals(calls, ["authenticate"]);
});

Deno.test("document upload authorization rejects ambiguous consecutive-dot names", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-upload-authorize", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({
    original_file_name: "file..pdf",
    mime_type: "application/pdf",
    document_type_code: "GENERAL",
    client_id: "30000000-0000-4000-8000-000000000001",
  }));
  assertEquals(response.status, 422);
  assertEquals(calls, ["authenticate"]);
});

Deno.test("document upload authorization rejects oversized JSON before parsing", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-upload-authorize", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({}, {
    headers: { "content-length": "20000" },
  }));
  assertEquals(response.status, 422);
  assertEquals(calls, ["authenticate"]);
});

Deno.test("document upload completion hashes trusted downloaded bytes and stops at awaiting scan", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-upload-complete", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.status, "AWAITING_SCAN");
  assertEquals(body.data.verified_mime_type, "application/pdf");
  assert(typeof body.data.sha256 === "string");
  assert(!JSON.stringify(body).includes("temporary/"));
});

Deno.test("document upload completion rejects malformed signatures and removes temporary object best effort", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-upload-complete", {
    loadEnv: env,
    authenticate: mockAuth({ calls, downloadText: "not a pdf" }),
  });
  const response = await handler(request({ upload_id: uploadId }));
  assertEquals(response.status, 422);
  assert(calls.some((call) => call.startsWith("remove:temporary/")));
});

Deno.test("document access proxies bytes instead of returning a reusable signed URL", async () => {
  const calls: string[] = [];
  const handler = createDocumentStorageHandler("document-access", {
    loadEnv: env,
    authenticate: mockAuth({ calls }),
  });
  const response = await handler(
    request({ document_id: documentId, purpose: "preview" }),
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Content-Type"), "application/pdf");
  assertEquals(
    response.headers.get("Content-Disposition"),
    'inline; filename="visible.pdf"',
  );
  const text = await response.text();
  assertEquals(text, "%PDF-123");
  assert(!calls.some((call) => call.startsWith("signed:")));
});

Deno.test("document storage handlers map missing JWT to safe 401", async () => {
  const handler = createDocumentStorageHandler("document-upload-authorize", {
    loadEnv: env,
    authenticate: () => {
      throw unauthorized();
    },
  });
  const response = await handler(request({}));
  assertEquals(response.status, 401);
  const body = await response.json();
  assertEquals(body.data, {});
});
