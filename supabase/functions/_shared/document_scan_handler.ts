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

const BUCKET = "documents-private";
const MAX_JSON_BODY_BYTES = 4096;
const SCANNER_TIMEOUT_MS = 10_000;
const SCANNER_RESPONSE_MAX_BYTES = 8192;
const AUTHZ_ERROR_CODES = new Set(["42501", "PGRST301"]);
const VALIDATION_ERROR_CODES = new Set(["23514", "23505"]);

type ScanVerdict = "CLEAN" | "MALICIOUS" | "ERROR";

interface RpcError {
  code?: string;
  message?: string;
}

type RpcResult = { data: unknown; error: RpcError | null };
type StorageResult<T> = { data: T | null; error: RpcError | null };

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

export interface ScannerResult {
  verdict: ScanVerdict;
  scanner_version?: string;
  signature_database_version?: string;
  malware_name?: string;
  failure_category?: string;
}

export interface ScannerAdapter {
  scan(bytes: Uint8Array, signal: AbortSignal): Promise<ScannerResult>;
}

export interface DocumentScanDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
  scanner?: ScannerAdapter;
}

export type ScannerFetch = (
  input: URL,
  init: RequestInit,
) => Promise<Response>;

export function createDocumentScanHandler(
  deps: DocumentScanDependencies = {},
) {
  return async (req: Request): Promise<Response> => {
    const env = (deps.loadEnv ?? loadAppEnv)();
    const requestId = requestIdFromHeaders(req.headers);
    try {
      if (req.method === "OPTIONS") {
        return optionsResponse(req, env.appOrigin);
      }
      if (req.method !== "POST") {
        throw new SafeError(405, "bad_request", "Method is not allowed.");
      }
      requireAllowedOrigin(req, env.appOrigin);
      const auth = await (deps.authenticate ?? authenticateRequest)(req, env);
      enforceJsonBodyLimit(req);
      const body = await readJsonObject(req);
      rejectUnknownFields(body, ["upload_id"]);
      const uploadId = uuidValue(body.upload_id, "Upload ID");
      const result = await processUpload(uploadId, auth, requestId, deps);
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

async function processUpload(
  uploadId: string,
  auth: AuthenticatedContext,
  requestId: string,
  deps: DocumentScanDependencies,
): Promise<Record<string, unknown>> {
  const pendingFinalization = await tryPrepareFinalization(
    auth,
    uploadId,
    requestId,
  );
  if (pendingFinalization) {
    return await finalizePreparedUpload(
      auth,
      pendingFinalization,
      uploadId,
      requestId,
    );
  }

  const started = firstRow(
    (await rpc(auth, "server_owner_start_document_scan", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_upload_id: uploadId,
      p_request_identifier: requestId,
    })).data,
  );
  const scanId = stringField(started, "scan_id");
  const bucket = stringField(started, "storage_bucket");
  const tempKey = stringField(started, "storage_object_key");
  const expectedSize = numberField(started, "verified_file_size_bytes");
  const expectedHash = hexField(started, "verified_sha256_hash");
  const downloaded = await downloadBytes(auth, bucket, tempKey);
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", arrayBufferOf(downloaded)),
  );
  const actualHash = byteaHex(digest);
  if (downloaded.byteLength !== expectedSize || actualHash !== expectedHash) {
    await recordResult(
      auth,
      scanId,
      "ERROR",
      actualHash,
      downloaded.byteLength,
      {
        verdict: "ERROR",
        failure_category: "hash_mismatch",
      },
      requestId,
    );
    throw validationFailed("Document scan request cannot be completed.");
  }

  const scan = await runScanner(
    deps.scanner ?? productionScanner(),
    downloaded,
  );
  await recordResult(
    auth,
    scanId,
    scan.verdict,
    actualHash,
    downloaded.byteLength,
    scan,
    requestId,
  );
  if (scan.verdict !== "CLEAN") {
    return {
      upload_id: uploadId,
      status: scan.verdict === "MALICIOUS" ? "QUARANTINED" : "SCAN_FAILED",
    };
  }

  const prepared = firstRow(
    (await rpc(auth, "server_owner_prepare_clean_document_finalization", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_upload_id: uploadId,
      p_request_identifier: requestId,
    })).data,
  );
  return await finalizePreparedUpload(auth, prepared, uploadId, requestId);
}

export function createHttpsScannerAdapter(
  env: { DOCUMENT_SCANNER_URL?: string; DOCUMENT_SCANNER_TOKEN?: string },
  scannerFetch: ScannerFetch = fetch,
): ScannerAdapter {
  return {
    async scan(bytes: Uint8Array, signal: AbortSignal): Promise<ScannerResult> {
      const url = env.DOCUMENT_SCANNER_URL?.trim();
      const token = env.DOCUMENT_SCANNER_TOKEN?.trim();
      if (!url || !token) {
        return { verdict: "ERROR", failure_category: "scanner_unavailable" };
      }
      let endpoint: URL;
      try {
        endpoint = new URL(url);
      } catch {
        return { verdict: "ERROR", failure_category: "scanner_unavailable" };
      }
      if (endpoint.protocol !== "https:") {
        return { verdict: "ERROR", failure_category: "scanner_unavailable" };
      }
      try {
        const response = await scannerFetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/octet-stream",
          },
          body: arrayBufferOf(bytes),
          redirect: "manual",
          signal,
        });
        if (!response.ok) {
          return { verdict: "ERROR", failure_category: "scanner_unavailable" };
        }
        const json = await readLimitedScannerJson(response);
        return normalizeScannerResponse(json);
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") {
          return { verdict: "ERROR", failure_category: "timeout" };
        }
        return { verdict: "ERROR", failure_category: "network_error" };
      }
    },
  };
}

async function finalizePreparedUpload(
  auth: AuthenticatedContext,
  prepared: Record<string, unknown>,
  uploadId: string,
  requestId: string,
): Promise<Record<string, unknown>> {
  const bucket = stringField(prepared, "storage_bucket");
  const tempKey = stringField(prepared, "temporary_storage_object_key");
  const finalKey = stringField(prepared, "final_storage_object_key");
  const mimeType = stringField(prepared, "verified_mime_type");
  const expectedSize = numberField(prepared, "verified_file_size_bytes");
  const expectedHash = hexField(prepared, "verified_sha256_hash");
  const existingFinal = await tryDownloadBytes(auth, bucket, finalKey);
  let finalDownloaded: Uint8Array;
  if (existingFinal) {
    finalDownloaded = existingFinal;
  } else {
    const trustedTemp = await downloadBytes(auth, bucket, tempKey);
    await assertTrustedBytes(trustedTemp, expectedSize, expectedHash);
    await uploadFinalObject(auth, bucket, finalKey, trustedTemp, mimeType);
    finalDownloaded = await downloadBytes(auth, bucket, finalKey);
  }
  await assertTrustedBytes(finalDownloaded, expectedSize, expectedHash);
  const finalDigest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", arrayBufferOf(finalDownloaded)),
  );
  const finalized = firstRow(
    (await rpc(auth, "server_owner_finalize_clean_document_upload", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_upload_id: uploadId,
      p_verified_final_sha256_hash: byteaHex(finalDigest),
      p_verified_final_file_size_bytes: finalDownloaded.byteLength,
      p_request_identifier: requestId,
    })).data,
  );
  return {
    upload_id: uploadId,
    document_id: stringField(finalized, "document_id"),
    document_number: stringField(finalized, "document_number"),
    status: stringField(finalized, "status"),
  };
}

function productionScanner(): ScannerAdapter {
  return createHttpsScannerAdapter(Deno.env.toObject());
}

function normalizeScannerResponse(value: unknown): ScannerResult {
  if (!isRecord(value) || typeof value.result !== "string") {
    return { verdict: "ERROR", failure_category: "malformed_response" };
  }
  const result = value.result.toUpperCase();
  if (result === "CLEAN") {
    return {
      verdict: "CLEAN",
      scanner_version: stringOrUndefined(value.scanner_version),
      signature_database_version: stringOrUndefined(
        value.signature_database_version,
      ),
    };
  }
  if (result === "MALICIOUS") {
    return {
      verdict: "MALICIOUS",
      scanner_version: stringOrUndefined(value.scanner_version),
      signature_database_version: stringOrUndefined(
        value.signature_database_version,
      ),
      malware_name: stringOrUndefined(value.malware_name),
    };
  }
  if (result === "ERROR") {
    return { verdict: "ERROR", failure_category: "scanner_unavailable" };
  }
  return { verdict: "ERROR", failure_category: "unknown_result" };
}

async function runScanner(
  scanner: ScannerAdapter,
  bytes: Uint8Array,
): Promise<ScannerResult> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), SCANNER_TIMEOUT_MS);
  try {
    return await scanner.scan(bytes, controller.signal);
  } catch {
    return { verdict: "ERROR", failure_category: "network_error" };
  } finally {
    clearTimeout(timeout);
  }
}

async function recordResult(
  auth: AuthenticatedContext,
  scanId: string,
  result: ScanVerdict,
  hash: string,
  size: number,
  scan: ScannerResult,
  requestId: string,
): Promise<void> {
  await rpc(auth, "server_owner_record_document_scan_result", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_scan_id: scanId,
    p_result: result,
    p_scanned_sha256_hash: hash,
    p_scanned_file_size_bytes: size,
    p_scanner_version: scan.scanner_version ?? null,
    p_signature_database_version: scan.signature_database_version ?? null,
    p_failure_category: scan.failure_category ?? null,
    p_malware_name: scan.malware_name ?? null,
    p_request_identifier: requestId,
  });
}

async function downloadBytes(
  auth: AuthenticatedContext,
  bucket: string,
  path: string,
): Promise<Uint8Array> {
  if (bucket !== BUCKET) {
    throw validationFailed("Document scan request cannot be completed.");
  }
  const result = await serviceClient(auth).storage.from(bucket).download(path);
  if (result.error || !result.data) {
    throw validationFailed("Document scan request cannot be completed.");
  }
  return new Uint8Array(await result.data.arrayBuffer());
}

async function tryDownloadBytes(
  auth: AuthenticatedContext,
  bucket: string,
  path: string,
): Promise<Uint8Array | null> {
  if (bucket !== BUCKET) {
    throw validationFailed("Document scan request cannot be completed.");
  }
  const result = await serviceClient(auth).storage.from(bucket).download(path);
  if (result.error || !result.data) return null;
  return new Uint8Array(await result.data.arrayBuffer());
}

async function assertTrustedBytes(
  bytes: Uint8Array,
  expectedSize: number,
  expectedHash: string,
): Promise<void> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", arrayBufferOf(bytes)),
  );
  if (bytes.byteLength !== expectedSize || byteaHex(digest) !== expectedHash) {
    throw validationFailed(
      "Document finalization request cannot be completed.",
    );
  }
}

async function uploadFinalObject(
  auth: AuthenticatedContext,
  bucket: string,
  path: string,
  bytes: Uint8Array,
  mimeType: string,
): Promise<void> {
  if (bucket !== BUCKET || !path.startsWith("objects/")) {
    throw validationFailed(
      "Document finalization request cannot be completed.",
    );
  }
  const result = await serviceClient(auth).storage.from(bucket).upload(
    path,
    new Blob([arrayBufferOf(bytes)], { type: mimeType }),
    { contentType: mimeType, upsert: true },
  );
  if (result.error) {
    throw validationFailed(
      "Document finalization request cannot be completed.",
    );
  }
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
  ) {
    return result;
  }
  throw mapDatabaseError(result.error);
}

async function tryPrepareFinalization(
  auth: AuthenticatedContext,
  uploadId: string,
  requestId: string,
): Promise<Record<string, unknown> | null> {
  const result = await rpcAllowValidation(
    auth,
    "server_owner_prepare_clean_document_finalization",
    {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_upload_id: uploadId,
      p_request_identifier: requestId,
    },
  );
  if (result.error) return null;
  return firstRow(result.data);
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

function hexField(row: Record<string, unknown>, name: string): string {
  const value = stringField(row, name);
  return value.startsWith("\\x") ? value : `\\x${value}`;
}

function arrayBufferOf(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

function numberField(row: Record<string, unknown>, name: string): number {
  const value = row[name];
  if (typeof value === "number") return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function mapError(error: unknown): unknown {
  if (error instanceof SafeError) return error;
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

function mapDatabaseError(error: RpcError): SafeError {
  if (typeof error.code === "string" && AUTHZ_ERROR_CODES.has(error.code)) {
    return new SafeError(401, "unauthorized", "Operation is not authorized.");
  }
  if (
    typeof error.code === "string" && VALIDATION_ERROR_CODES.has(error.code)
  ) {
    return validationFailed("Document scan request cannot be completed.");
  }
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

async function readLimitedScannerJson(response: Response): Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) return await response.json();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > SCANNER_RESPONSE_MAX_BYTES) {
      throw new Error("scanner response too large");
    }
    chunks.push(value);
  }
  const body = new TextDecoder().decode(concatBytes(chunks, total));
  return JSON.parse(body);
}

function concatBytes(chunks: Uint8Array[], total: number): Uint8Array {
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return merged;
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
