import type { AppEnv } from "./env.ts";
import { loadAppEnv } from "./env.ts";
import { authenticateRequest } from "./auth.ts";
import type { AuthenticatedContext } from "./auth.ts";
import { corsHeaders, optionsResponse, requireAllowedOrigin } from "./cors.ts";
import { SafeError, validationFailed } from "./errors.ts";
import {
  errorEnvelope,
  readJsonObject,
  requestIdFromHeaders,
  successEnvelope,
} from "./http.ts";
import { byteaHex } from "./token.ts";
import { rejectUnknownFields, uuidValue } from "./validation.ts";
import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
  MagickGeometry,
} from "@imagemagick/magick-wasm";

const BUCKET = "documents-private";
const MAX_JSON_BODY_BYTES = 4096;
const MAX_PHOTO_BYTES = 5_242_880;
const MAX_DIMENSION = 6000;
const MAX_PIXELS = 12_000_000;
const THUMBNAIL_BOX = 320;
const PREVIEW_BOX = 1600;
const PROCESSOR_VERSION = "magick-wasm-0.0.35/package-12.5";
const AUTHZ_ERROR_CODES = new Set(["42501", "PGRST301"]);
const VALIDATION_ERROR_CODES = new Set(["23514", "23505"]);

type FailureCode =
  | "unsupported_mime"
  | "not_photograph_type"
  | "original_unavailable"
  | "original_hash_mismatch"
  | "decode_failed"
  | "dimensions_unavailable"
  | "source_dimensions_exceeded"
  | "decoded_pixels_exceeded"
  | "animated_image_unsupported"
  | "processor_timeout"
  | "processor_error"
  | "derivative_upload_failed"
  | "derivative_verify_failed";

type StorageResult<T> = { data: T | null; error: RpcError | null };
type RpcResult = { data: unknown; error: RpcError | null };

interface RpcError {
  code?: string;
  message?: string;
}

interface StorageClient {
  from(bucket: string): {
    download(path: string): Promise<StorageResult<Blob>>;
    upload(
      path: string,
      body: Blob,
      options: { contentType: string; upsert: boolean },
    ): Promise<StorageResult<unknown>>;
  };
}

interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
  storage: StorageClient;
}

export interface DocumentImageDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
  wasmBytes?: () => Promise<Uint8Array>;
}

export interface ImageDimensions {
  width: number;
  height: number;
  animated?: boolean;
}

let initialized: Promise<void> | null = null;

export function createDocumentImageHandler(
  deps: DocumentImageDependencies = {},
) {
  return async (req: Request): Promise<Response> => {
    const env = (deps.loadEnv ?? loadAppEnv)();
    const requestId = requestIdFromHeaders(req.headers);
    try {
      if (req.method === "OPTIONS") return optionsResponse(req, env.appOrigin);
      if (req.method !== "POST") {
        throw new SafeError(405, "bad_request", "Method is not allowed.");
      }
      requireAllowedOrigin(req, env.appOrigin);
      const auth = await (deps.authenticate ?? authenticateRequest)(req, env);
      enforceJsonBodyLimit(req);
      const body = await readJsonObject(req);
      rejectUnknownFields(body, ["document_id"]);
      const documentId = uuidValue(body.document_id, "Document ID");
      const result = await processPhotograph(documentId, auth, requestId, deps);
      return successEnvelope(result, requestId, {
        headers: corsHeaders(env.appOrigin),
      });
    } catch (error) {
      return errorEnvelope(mapError(error), requestId, {
        headers: error instanceof SafeError && error.status === 403
          ? undefined
          : corsHeaders(env.appOrigin),
      });
    }
  };
}

async function processPhotograph(
  documentId: string,
  auth: AuthenticatedContext,
  requestId: string,
  deps: DocumentImageDependencies,
): Promise<Record<string, unknown>> {
  const prepared = firstRow(
    (await rpc(auth, "server_owner_prepare_document_image_processing", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_document_id: documentId,
      p_request_identifier: requestId,
    })).data,
  );
  if (stringField(prepared, "processing_status") === "READY") {
    return {
      document_id: documentId,
      status: "READY",
      thumbnail: "ready",
      preview: "ready",
    };
  }

  const bucket = stringField(prepared, "storage_bucket");
  const originalKey = stringField(prepared, "storage_object_key");
  const mimeType = stringField(prepared, "mime_type");
  const expectedHash = hexField(prepared, "source_sha256_hash");
  const expectedSize = numberField(prepared, "source_file_size_bytes");
  const thumbnailKey = stringField(prepared, "thumbnail_storage_object_key");
  const previewKey = stringField(prepared, "preview_storage_object_key");

  try {
    if (bucket !== BUCKET || !originalKey.startsWith("objects/")) {
      throw failure("original_unavailable");
    }
    if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
      throw failure("unsupported_mime");
    }
    if (expectedSize > MAX_PHOTO_BYTES) {
      throw failure("source_dimensions_exceeded");
    }
    const original = await downloadBytes(
      auth,
      bucket,
      originalKey,
      "original_unavailable",
    );
    if (original.byteLength !== expectedSize) {
      throw failure("original_hash_mismatch");
    }
    const sourceHash = byteaHex(
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", arrayBufferOf(original)),
      ),
    );
    if (sourceHash !== expectedHash) throw failure("original_hash_mismatch");
    const dimensions = inspectImageDimensions(original, mimeType);
    validateDimensions(dimensions);
    await ensureMagick(deps);
    const thumbnail = transformImage(original, THUMBNAIL_BOX, 78);
    const preview = transformImage(original, PREVIEW_BOX, 82);
    const thumbInfo = verifyWebpDerivative(thumbnail, THUMBNAIL_BOX);
    const previewInfo = verifyWebpDerivative(preview, PREVIEW_BOX);
    await putAndVerify(auth, bucket, thumbnailKey, thumbnail);
    await putAndVerify(auth, bucket, previewKey, preview);
    const thumbHash = byteaHex(
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", arrayBufferOf(thumbnail)),
      ),
    );
    const previewHash = byteaHex(
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", arrayBufferOf(preview)),
      ),
    );
    const completed = firstRow(
      (await rpc(auth, "server_owner_complete_document_image_processing", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_document_id: documentId,
        p_source_sha256_hash: sourceHash,
        p_source_width: dimensions.width,
        p_source_height: dimensions.height,
        p_thumbnail_file_size_bytes: thumbnail.byteLength,
        p_thumbnail_sha256_hash: thumbHash,
        p_thumbnail_width: thumbInfo.width,
        p_thumbnail_height: thumbInfo.height,
        p_preview_file_size_bytes: preview.byteLength,
        p_preview_sha256_hash: previewHash,
        p_preview_width: previewInfo.width,
        p_preview_height: previewInfo.height,
        p_processor_version: PROCESSOR_VERSION,
        p_request_identifier: requestId,
      })).data,
    );
    return {
      document_id: stringField(completed, "document_id"),
      status: stringField(completed, "processing_status"),
      thumbnail_width: thumbInfo.width,
      thumbnail_height: thumbInfo.height,
      preview_width: previewInfo.width,
      preview_height: previewInfo.height,
    };
  } catch (error) {
    const code = error instanceof PhotographFailure
      ? error.code
      : "processor_error";
    await rpcAllowValidation(
      auth,
      "server_owner_fail_document_image_processing",
      {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_document_id: documentId,
        p_failure_code: code,
        p_request_identifier: requestId,
      },
    );
    throw validationFailed(
      "Photograph processing request cannot be completed.",
    );
  }
}

async function ensureMagick(deps: DocumentImageDependencies): Promise<void> {
  initialized ??= (async () => {
    const bytes = deps.wasmBytes ? await deps.wasmBytes() : await Deno.readFile(
      new URL("../document-process-photograph/magick.wasm", import.meta.url),
    );
    await initializeImageMagick(bytes);
  })();
  await initialized;
}

export function inspectImageDimensions(
  bytes: Uint8Array,
  mimeType: string,
): ImageDimensions {
  if (mimeType === "image/png") return inspectPng(bytes);
  if (mimeType === "image/jpeg") return inspectJpeg(bytes);
  if (mimeType === "image/webp") return inspectWebp(bytes);
  throw failure("unsupported_mime");
}

function inspectPng(bytes: Uint8Array): ImageDimensions {
  if (
    bytes.length < 33 || bytes[0] !== 0x89 || text(bytes.slice(1, 4)) !== "PNG"
  ) {
    throw failure("dimensions_unavailable");
  }
  return { width: u32be(bytes, 16), height: u32be(bytes, 20) };
}

function inspectJpeg(bytes: Uint8Array): ImageDimensions {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw failure("dimensions_unavailable");
  }
  let offset = 2;
  while (offset + 3 < bytes.length) {
    while (offset < bytes.length && bytes[offset] === 0xff) offset++;
    if (offset >= bytes.length) break;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (offset + 2 > bytes.length) throw failure("dimensions_unavailable");
    const length = u16be(bytes, offset);
    if (length < 2 || offset + length > bytes.length) {
      throw failure("dimensions_unavailable");
    }
    if (
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf)
    ) {
      if (length < 7) throw failure("dimensions_unavailable");
      return {
        height: u16be(bytes, offset + 3),
        width: u16be(bytes, offset + 5),
      };
    }
    offset += length;
  }
  throw failure("dimensions_unavailable");
}

function inspectWebp(bytes: Uint8Array): ImageDimensions {
  if (
    bytes.length < 30 || text(bytes.slice(0, 4)) !== "RIFF" ||
    text(bytes.slice(8, 12)) !== "WEBP"
  ) {
    throw failure("dimensions_unavailable");
  }
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const chunk = text(bytes.slice(offset, offset + 4));
    const size = u32le(bytes, offset + 4);
    const data = offset + 8;
    if (size < 0 || data + size > bytes.length) {
      throw failure("dimensions_unavailable");
    }
    if (chunk === "VP8X") {
      if (size < 10) throw failure("dimensions_unavailable");
      if ((bytes[data] & 0x02) !== 0) {
        throw failure("animated_image_unsupported");
      }
      return {
        width: 1 + u24le(bytes, data + 4),
        height: 1 + u24le(bytes, data + 7),
      };
    }
    if (chunk === "VP8 ") {
      if (
        size < 10 || bytes[data + 3] !== 0x9d || bytes[data + 4] !== 0x01 ||
        bytes[data + 5] !== 0x2a
      ) {
        throw failure("dimensions_unavailable");
      }
      return {
        width: u16le(bytes, data + 6) & 0x3fff,
        height: u16le(bytes, data + 8) & 0x3fff,
      };
    }
    if (chunk === "VP8L") {
      if (size < 5 || bytes[data] !== 0x2f) {
        throw failure("dimensions_unavailable");
      }
      const bits = bytes[data + 1] | (bytes[data + 2] << 8) |
        (bytes[data + 3] << 16) | (bytes[data + 4] << 24);
      return {
        width: (bits & 0x3fff) + 1,
        height: ((bits >> 14) & 0x3fff) + 1,
      };
    }
    offset = data + size + (size % 2);
  }
  throw failure("dimensions_unavailable");
}

function validateDimensions(dimensions: ImageDimensions): void {
  if (
    !Number.isInteger(dimensions.width) ||
    !Number.isInteger(dimensions.height) || dimensions.width <= 0 ||
    dimensions.height <= 0
  ) {
    throw failure("dimensions_unavailable");
  }
  if (dimensions.width > MAX_DIMENSION || dimensions.height > MAX_DIMENSION) {
    throw failure("source_dimensions_exceeded");
  }
  if (dimensions.width > Math.floor(MAX_PIXELS / dimensions.height)) {
    throw failure("decoded_pixels_exceeded");
  }
}

function transformImage(
  bytes: Uint8Array,
  box: number,
  quality: number,
): Uint8Array {
  try {
    let output = new Uint8Array();
    ImageMagick.read(bytes, (image) => {
      image.autoOrient();
      image.strip();
      const geometry = new MagickGeometry(box, box);
      geometry.greater = true;
      image.resize(geometry);
      image.quality = quality;
      image.write(MagickFormat.WebP, (data) => {
        output = data.slice();
      });
    });
    if (!output.length) throw failure("processor_error");
    return output;
  } catch (error) {
    if (error instanceof PhotographFailure) throw error;
    throw failure("decode_failed");
  }
}

function verifyWebpDerivative(bytes: Uint8Array, box: number): ImageDimensions {
  const dimensions = inspectWebp(bytes);
  if (
    dimensions.width <= 0 || dimensions.height <= 0 || dimensions.width > box ||
    dimensions.height > box
  ) {
    throw failure("derivative_verify_failed");
  }
  if (containsMetadataMarker(bytes)) throw failure("derivative_verify_failed");
  return dimensions;
}

export function containsMetadataMarker(bytes: Uint8Array): boolean {
  const sample = text(bytes).toLowerCase();
  return ["exif", "gps", "xmp", "iptc", "camera", "make", "model", "filename"]
    .some((marker) => sample.includes(marker));
}

async function putAndVerify(
  auth: AuthenticatedContext,
  bucket: string,
  key: string,
  bytes: Uint8Array,
): Promise<void> {
  if (
    bucket !== BUCKET || !key.startsWith("derivatives/") ||
    !key.endsWith(".webp")
  ) {
    throw failure("derivative_upload_failed");
  }
  const upload = await serviceClient(auth).storage.from(bucket).upload(
    key,
    new Blob([arrayBufferOf(bytes)], { type: "image/webp" }),
    { contentType: "image/webp", upsert: true },
  );
  if (upload.error) throw failure("derivative_upload_failed");
  const verified = await downloadBytes(
    auth,
    bucket,
    key,
    "derivative_verify_failed",
  );
  if (verified.byteLength !== bytes.byteLength) {
    throw failure("derivative_verify_failed");
  }
  const expected = byteaHex(
    new Uint8Array(await crypto.subtle.digest("SHA-256", arrayBufferOf(bytes))),
  );
  const actual = byteaHex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", arrayBufferOf(verified)),
    ),
  );
  if (expected !== actual) throw failure("derivative_verify_failed");
}

async function downloadBytes(
  auth: AuthenticatedContext,
  bucket: string,
  key: string,
  code: FailureCode,
): Promise<Uint8Array> {
  if (bucket !== BUCKET) throw failure(code);
  const result = await serviceClient(auth).storage.from(bucket).download(key);
  if (result.error || !result.data) throw failure(code);
  return new Uint8Array(await result.data.arrayBuffer());
}

function enforceJsonBodyLimit(req: Request): void {
  const length = req.headers.get("content-length");
  if (length && Number(length) > MAX_JSON_BODY_BYTES) {
    throw validationFailed("Request body is too large.");
  }
}

async function rpc(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
): Promise<RpcResult> {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) return result;
  throw mapDatabaseError(result.error);
}

async function rpcAllowValidation(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
): Promise<RpcResult> {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) return result;
  if (
    typeof result.error.code === "string" &&
    VALIDATION_ERROR_CODES.has(result.error.code)
  ) return result;
  throw mapDatabaseError(result.error);
}

function mapDatabaseError(error: RpcError): SafeError {
  if (typeof error.code === "string" && AUTHZ_ERROR_CODES.has(error.code)) {
    return new SafeError(401, "unauthorized", "Operation is not authorized.");
  }
  if (typeof error.message === "string" && isFailureCode(error.message)) {
    return validationFailed(
      "Photograph processing request cannot be completed.",
    );
  }
  if (
    typeof error.code === "string" && VALIDATION_ERROR_CODES.has(error.code)
  ) {
    return validationFailed(
      "Photograph processing request cannot be completed.",
    );
  }
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

function mapError(error: unknown): unknown {
  if (error instanceof SafeError) return error;
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

class PhotographFailure extends Error {
  constructor(readonly code: FailureCode) {
    super(code);
  }
}

function failure(code: FailureCode): PhotographFailure {
  return new PhotographFailure(code);
}

function isFailureCode(value: string): value is FailureCode {
  return [
    "unsupported_mime",
    "not_photograph_type",
    "original_unavailable",
    "original_hash_mismatch",
    "decode_failed",
    "dimensions_unavailable",
    "source_dimensions_exceeded",
    "decoded_pixels_exceeded",
    "animated_image_unsupported",
    "processor_timeout",
    "processor_error",
    "derivative_upload_failed",
    "derivative_verify_failed",
  ].includes(value);
}

function serviceClient(auth: AuthenticatedContext): ServiceClient {
  return auth.serviceClient as unknown as ServiceClient;
}

function firstRow(data: unknown): Record<string, unknown> {
  if (Array.isArray(data) && data.length > 0 && isRecord(data[0])) {
    return data[0];
  }
  if (isRecord(data)) return data;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function stringField(row: Record<string, unknown>, name: string): string {
  const value = row[name];
  if (typeof value === "string" && value) return value;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function numberField(row: Record<string, unknown>, name: string): number {
  const value = row[name];
  if (typeof value === "number") return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function hexField(row: Record<string, unknown>, name: string): string {
  const value = stringField(row, name);
  return value.startsWith("\\x") ? value : `\\x${value}`;
}

function u16be(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function u16le(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function u24le(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

function u32be(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] * 0x1000000) +
    ((bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) |
      bytes[offset + 3])) >>> 0;
}

function u32le(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) |
    (bytes[offset + 3] * 0x1000000)) >>> 0;
}

function text(bytes: Uint8Array): string {
  return new TextDecoder("latin1").decode(bytes);
}

function arrayBufferOf(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
