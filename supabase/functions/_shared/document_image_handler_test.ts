import type { AppEnv } from "./env.ts";
import type { AuthenticatedContext } from "./auth.ts";
import {
  containsMetadataMarker,
  createDocumentImageHandler,
  inspectImageDimensions,
} from "./document_image_handler.ts";
import {
  initializeImageMagick,
  MagickColor,
  MagickFormat,
  MagickImage,
} from "@imagemagick/magick-wasm";

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

const documentId = "10000000-0000-4000-8000-000000000125";
const actor = "00000000-0000-4000-8000-000000000125";
const originalKey = `objects/${documentId}/opaque`;
const thumbnailKey =
  `derivatives/${documentId}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/thumbnail.webp`;
const previewKey =
  `derivatives/${documentId}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/preview.webp`;

const env = (): AppEnv => ({
  supabaseUrl: "http://127.0.0.1:54321",
  publishableKey: "anon",
  serviceRoleKey: "service",
  jwksUrl: "http://127.0.0.1:54321/auth/v1/.well-known/jwks.json",
  appBaseUrl: "http://localhost:3000",
  appOrigin: "http://localhost:3000",
});

let magickInit: Promise<void> | null = null;

async function wasmBytes(): Promise<Uint8Array> {
  return await Deno.readFile(
    new URL("../document-process-photograph/magick.wasm", import.meta.url),
  );
}

async function ensureFixtureMagick(): Promise<void> {
  magickInit ??= initializeImageMagick(await wasmBytes());
  await magickInit;
}

async function makeFixture(
  format: typeof MagickFormat[keyof typeof MagickFormat],
): Promise<Uint8Array> {
  await ensureFixtureMagick();
  const image = MagickImage.create(new MagickColor(255, 0, 0, 128), 4, 2);
  try {
    let output = new Uint8Array();
    image.write(format, (data) => {
      output = data.slice();
    });
    return output;
  } finally {
    image.dispose();
  }
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", arrayBufferOf(bytes)),
  );
  return `\\x${
    Array.from(digest).map((byte) => byte.toString(16).padStart(2, "0")).join(
      "",
    )
  }`;
}

function request(body: Record<string, unknown>): Request {
  return new Request("http://localhost/document-process-photograph", {
    method: "POST",
    headers: {
      Origin: "http://localhost:3000",
      Authorization: "Bearer jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function mockAuth(
  options: { original: Uint8Array; calls: string[] },
): AuthenticatedContext {
  const objects = new Map<string, Uint8Array>([[
    originalKey,
    options.original,
  ]]);
  return {
    actorAuthSubject: actor,
    token: "jwt",
    serviceClient: {
      rpc: async (name: string, args: Record<string, unknown>) => {
        options.calls.push(`rpc:${name}`);
        if (name === "server_owner_prepare_document_image_processing") {
          return {
            data: [{
              document_id: documentId,
              storage_bucket: "documents-private",
              storage_object_key: originalKey,
              mime_type: args.p_document_id === "png"
                ? "image/png"
                : "image/webp",
              source_file_size_bytes: options.original.byteLength,
              source_sha256_hash: await sha256Hex(options.original),
              document_type_code: "PROGRESS_PHOTOGRAPH",
              processing_status: "PROCESSING",
              thumbnail_storage_object_key: thumbnailKey,
              preview_storage_object_key: previewKey,
            }],
            error: null,
          };
        }
        if (name === "server_owner_complete_document_image_processing") {
          assertEquals(args.p_document_id, documentId);
          assert(args.p_thumbnail_file_size_bytes);
          assert(args.p_preview_file_size_bytes);
          return {
            data: [{
              document_id: documentId,
              processing_status: "READY",
              thumbnail_storage_object_key: thumbnailKey,
              preview_storage_object_key: previewKey,
            }],
            error: null,
          };
        }
        if (name === "server_owner_fail_document_image_processing") {
          return {
            data: [{
              document_id: documentId,
              processing_status: "FAILED",
              failure_code: args.p_failure_code,
            }],
            error: null,
          };
        }
        return { data: null, error: null };
      },
      storage: {
        from: (bucket: string) => {
          options.calls.push(`storage:${bucket}`);
          return {
            download: (path: string) => {
              options.calls.push(`download:${path}`);
              const bytes = objects.get(path);
              return Promise.resolve({
                data: bytes ? new Blob([arrayBufferOf(bytes)]) : null,
                error: bytes ? null : { code: "404" },
              });
            },
            upload: async (path: string, body: Blob) => {
              options.calls.push(`upload:${path}`);
              objects.set(path, new Uint8Array(await body.arrayBuffer()));
              return { data: {}, error: null };
            },
          };
        },
      },
    },
  } as unknown as AuthenticatedContext;
}

Deno.test("dimension inspection reads PNG and WebP before full decode", async () => {
  const png = await makeFixture(MagickFormat.Png);
  const webp = await makeFixture(MagickFormat.WebP);
  assertEquals(inspectImageDimensions(png, "image/png"), {
    width: 4,
    height: 2,
  });
  assertEquals(inspectImageDimensions(webp, "image/webp"), {
    width: 4,
    height: 2,
  });
});

function arrayBufferOf(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

Deno.test("animated WebP is rejected from header metadata", () => {
  const webp = new Uint8Array(30);
  webp.set(new TextEncoder().encode("RIFF"), 0);
  webp.set(new TextEncoder().encode("WEBPVP8X"), 8);
  webp[16] = 10;
  webp[20] = 0x02;
  let failed = false;
  try {
    inspectImageDimensions(webp, "image/webp");
  } catch {
    failed = true;
  }
  assert(failed);
});

Deno.test("photograph handler creates verified sanitized WebP derivatives", async () => {
  const original = await makeFixture(MagickFormat.WebP);
  const calls: string[] = [];
  const handler = createDocumentImageHandler({
    loadEnv: env,
    authenticate: () => Promise.resolve(mockAuth({ original, calls })),
    wasmBytes,
  });
  const response = await handler(request({ document_id: documentId }));
  assertEquals(response.status, 200);
  assert(calls.includes("rpc:server_owner_prepare_document_image_processing"));
  assert(calls.includes("rpc:server_owner_complete_document_image_processing"));
  assert(calls.includes(`upload:${thumbnailKey}`));
  assert(calls.includes(`upload:${previewKey}`));
});

Deno.test("metadata marker helper rejects EXIF GPS style payloads", () => {
  assert(
    containsMetadataMarker(new TextEncoder().encode("Exif GPS Camera Model")),
  );
  assert(
    !containsMetadataMarker(
      new Uint8Array([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]),
    ),
  );
});
