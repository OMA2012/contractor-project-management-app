import type { AppEnv } from "./env.ts";
import { loadAppEnv } from "./env.ts";
import { authenticateRequest } from "./auth.ts";
import type { AuthenticatedContext } from "./auth.ts";
import { corsHeaders, optionsResponse, requireAllowedOrigin } from "./cors.ts";
import { SafeError, unauthorized, validationFailed } from "./errors.ts";
import {
  errorEnvelope,
  readJsonObject,
  requestIdFromHeaders,
  successEnvelope,
} from "./http.ts";
import { base64Url, byteaHex } from "./token.ts";
import {
  rejectUnknownFields,
  trimmedNonblank,
  uuidValue,
} from "./validation.ts";

const BUCKET = "documents-private";
const MAX_BYTES = 26_214_400;
const MAX_JSON_BODY_BYTES = 16_384;
const AUTHZ_ERROR_CODES = new Set(["42501", "PGRST301"]);
const ALLOWED = new Map([
  ["pdf", "application/pdf"],
  ["jpg", "image/jpeg"],
  ["jpeg", "image/jpeg"],
  ["png", "image/png"],
  ["webp", "image/webp"],
]);
const DANGEROUS_EXTENSION =
  /\.(exe|dll|bat|cmd|ps1|sh|js|jar|com|msi|vbs|scr|zip|rar|7z|tar|gz|docm|xlsm|pptm)(\.|$)/i;

type DocumentStorageKind =
  | "document-upload-authorize"
  | "document-upload-complete"
  | "document-access";

interface RpcError {
  code?: string;
  message?: string;
}

type RpcResult = { data: unknown; error: RpcError | null };
type StorageResult<T> = { data: T | null; error: RpcError | null };

interface StorageClient {
  from(bucket: string): {
    createSignedUploadUrl(path: string): Promise<
      StorageResult<{
        signedUrl?: string;
        token?: string;
        path?: string;
      }>
    >;
    download(path: string): Promise<StorageResult<Blob>>;
    remove(paths: string[]): Promise<StorageResult<unknown>>;
  };
}

interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
  storage: StorageClient;
}

export interface DocumentStorageDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
}

export function createDocumentStorageHandler(
  kind: DocumentStorageKind,
  deps: DocumentStorageDependencies = {},
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
      if (kind === "document-upload-authorize") {
        return successEnvelope(
          await authorizeUpload(body, auth, requestId),
          requestId,
          {
            headers: corsHeaders(env.appOrigin),
          },
        );
      }
      if (kind === "document-upload-complete") {
        return successEnvelope(
          await completeUpload(body, auth, requestId),
          requestId,
          {
            headers: corsHeaders(env.appOrigin),
          },
        );
      }
      return await accessDocument(body, auth, requestId, env.appOrigin);
    } catch (error) {
      return errorEnvelope(mapError(error), requestId, {
        headers: error instanceof SafeError && error.status === 403
          ? undefined
          : corsHeaders(env.appOrigin),
      });
    }
  };
}

function enforceJsonBodyLimit(req: Request): void {
  const length = req.headers.get("content-length");
  if (length && Number(length) > MAX_JSON_BODY_BYTES) {
    throw validationFailed("Request body is too large.");
  }
}

async function authorizeUpload(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  if (
    body.client_payment_id !== undefined &&
    body.document_type_code === undefined
  ) {
    return await authorizeClientTransferEvidenceUpload(body, auth, requestId);
  }
  rejectUnknownFields(body, [
    "original_file_name",
    "mime_type",
    "document_type_code",
    "client_visible",
    "client_id",
    "project_id",
    "task_id",
    "progress_update_id",
    "client_payment_id",
    "payment_request_id",
    "project_expense_id",
    "currency_exchange_id",
  ]);
  const originalFileName = validateFileName(body.original_file_name);
  const mimeType = validateDeclaredMime(originalFileName, body.mime_type);
  const documentTypeCode = trimmedNonblank(
    body.document_type_code,
    "Document type",
  );
  const token = randomObjectToken();
  const reserve = await rpc(auth, "server_owner_reserve_document_upload", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_storage_object_token: token,
    p_original_file_name: originalFileName,
    p_declared_mime_type: mimeType,
    p_document_type_code: documentTypeCode,
    p_requested_client_visible: body.client_visible === true,
    p_client_id: optionalUuid(body.client_id, "Client ID"),
    p_project_id: optionalUuid(body.project_id, "Project ID"),
    p_task_id: optionalUuid(body.task_id, "Task ID"),
    p_progress_update_id: optionalUuid(
      body.progress_update_id,
      "Progress update ID",
    ),
    p_request_identifier: requestId,
    p_client_payment_id: optionalUuid(
      body.client_payment_id,
      "Client payment ID",
    ),
    p_payment_request_id: optionalUuid(
      body.payment_request_id,
      "Payment request ID",
    ),
    p_project_expense_id: optionalUuid(
      body.project_expense_id,
      "Project expense ID",
    ),
    p_currency_exchange_id: optionalUuid(
      body.currency_exchange_id,
      "Currency exchange ID",
    ),
  });
  const row = firstRow(reserve.data);
  const bucket = stringField(row, "storage_bucket");
  const objectKey = stringField(row, "storage_object_key");
  if (bucket !== BUCKET || !objectKey.startsWith("temporary/")) {
    throw new SafeError(
      500,
      "internal_error",
      "Database response was invalid.",
    );
  }
  const signed = await serviceClient(auth).storage.from(bucket)
    .createSignedUploadUrl(objectKey);
  if (signed.error || !signed.data?.signedUrl) {
    throw new SafeError(503, "internal_error", "Upload authorization failed.");
  }
  return {
    upload_id: stringField(row, "upload_id"),
    expires_at: stringField(row, "expires_at"),
    upload_url: signed.data.signedUrl,
    upload_token: signed.data.token ?? null,
    method: "PUT",
    max_file_size_bytes: MAX_BYTES,
    allowed_mime_types: Array.from(new Set(ALLOWED.values())),
  };
}

async function authorizeClientTransferEvidenceUpload(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  rejectUnknownFields(body, [
    "original_file_name",
    "mime_type",
    "client_payment_id",
  ]);
  const originalFileName = validateFileName(body.original_file_name);
  const mimeType = validateDeclaredMime(originalFileName, body.mime_type);
  const token = randomObjectToken();
  const reserve = await rpc(
    auth,
    "current_client_reserve_transfer_evidence_upload",
    {
      p_verified_client_auth_subject: auth.actorAuthSubject,
      p_storage_object_token: token,
      p_original_file_name: originalFileName,
      p_declared_mime_type: mimeType,
      p_client_payment_id: uuidValue(
        body.client_payment_id,
        "Client payment ID",
      ),
      p_request_identifier: requestId,
    },
  );
  const row = firstRow(reserve.data);
  const bucket = stringField(row, "storage_bucket");
  const objectKey = stringField(row, "storage_object_key");
  if (bucket !== BUCKET || !objectKey.startsWith("temporary/")) {
    throw new SafeError(
      500,
      "internal_error",
      "Database response was invalid.",
    );
  }
  const signed = await serviceClient(auth).storage.from(bucket)
    .createSignedUploadUrl(objectKey);
  if (signed.error || !signed.data?.signedUrl) {
    throw new SafeError(503, "internal_error", "Upload authorization failed.");
  }
  return {
    upload_id: stringField(row, "upload_id"),
    expires_at: stringField(row, "expires_at"),
    upload_url: signed.data.signedUrl,
    upload_token: signed.data.token ?? null,
    method: "PUT",
    max_file_size_bytes: MAX_BYTES,
    allowed_mime_types: Array.from(new Set(ALLOWED.values())),
  };
}

async function completeUpload(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  rejectUnknownFields(body, ["upload_id"]);
  const uploadId = uuidValue(body.upload_id, "Upload ID");
  let isClientEvidence = false;
  let lookup = await rpcAllowUnauthorized(
    auth,
    "server_owner_document_upload_storage_context",
    {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_upload_id: uploadId,
    },
  );
  if (lookup.error) {
    lookup = await rpc(
      auth,
      "current_client_transfer_evidence_upload_storage_context",
      {
        p_verified_client_auth_subject: auth.actorAuthSubject,
        p_upload_id: uploadId,
      },
    );
    isClientEvidence = true;
  }
  const uploadRow = firstRow(lookup.data);
  const bucket = stringField(uploadRow, "storage_bucket");
  const objectKey = stringField(uploadRow, "storage_object_key");
  const blobResult = await serviceClient(auth).storage.from(bucket).download(
    objectKey,
  );
  if (blobResult.error || !blobResult.data) {
    throw validationFailed("Uploaded object is not available.");
  }
  const bytes = new Uint8Array(await blobResult.data.arrayBuffer());
  const verifiedMime = verifiedMimeFromMagic(bytes);
  if (bytes.byteLength <= 0 || bytes.byteLength > MAX_BYTES || !verifiedMime) {
    await bestEffortRemove(auth, bucket, objectKey);
    throw validationFailed("Uploaded object failed validation.");
  }
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const complete = await rpc(
    auth,
    isClientEvidence
      ? "current_client_complete_transfer_evidence_upload"
      : "server_owner_complete_document_upload",
    isClientEvidence
      ? {
        p_verified_client_auth_subject: auth.actorAuthSubject,
        p_upload_id: uploadId,
        p_verified_mime_type: verifiedMime,
        p_verified_file_size_bytes: bytes.byteLength,
        p_verified_sha256_hash: byteaHex(digest),
        p_request_identifier: requestId,
      }
      : {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_upload_id: uploadId,
        p_verified_mime_type: verifiedMime,
        p_verified_file_size_bytes: bytes.byteLength,
        p_verified_sha256_hash: byteaHex(digest),
        p_request_identifier: requestId,
      },
  );
  const row = firstRow(complete.data);
  return {
    upload_id: stringField(row, "upload_id"),
    status: stringField(row, "status"),
    reserved_document_id: stringField(row, "reserved_document_id"),
    verified_mime_type: stringField(row, "verified_mime_type"),
    verified_file_size_bytes: numberField(row, "verified_file_size_bytes"),
    sha256: byteaHex(digest).slice(2),
  };
}

async function accessDocument(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
  appOrigin: string,
): Promise<Response> {
  rejectUnknownFields(body, ["document_id", "purpose", "mode"]);
  const documentId = uuidValue(body.document_id, "Document ID");
  const requestedMode = body.mode === "thumbnail"
    ? "thumbnail"
    : body.mode === "original"
    ? "original"
    : body.mode === "preview"
    ? "preview"
    : body.mode === "download"
    ? "download"
    : "";
  const purpose = requestedMode ||
    (body.purpose === "preview"
      ? "preview"
      : body.purpose === "download"
      ? "download"
      : "");
  if (!purpose) throw validationFailed("Document access purpose is invalid.");
  const access = await rpc(auth, "server_authorize_document_image_access", {
    p_verified_auth_subject: auth.actorAuthSubject,
    p_document_id: documentId,
    p_mode: purpose,
    p_request_identifier: requestId,
  });
  const row = firstRow(access.data);
  const bucket = stringField(row, "storage_bucket");
  const objectKey = stringField(row, "storage_object_key");
  const mimeType = stringField(row, "mime_type");
  if (
    purpose === "preview" &&
    !["application/pdf", "image/jpeg", "image/png", "image/webp"].includes(
      mimeType,
    )
  ) {
    throw validationFailed("Document cannot be previewed.");
  }
  const blobResult = await serviceClient(auth).storage.from(bucket).download(
    objectKey,
  );
  if (blobResult.error || !blobResult.data) {
    throw validationFailed("Document object is not available.");
  }
  return new Response(blobResult.data, {
    status: 200,
    headers: {
      ...Object.fromEntries(corsHeaders(appOrigin)),
      "Content-Type": mimeType,
      "Content-Disposition": stringField(row, "content_disposition"),
      "Cache-Control": "no-store",
      "X-Document-Number": stringField(row, "document_number"),
    },
  });
}

function validateFileName(value: unknown): string {
  const name = trimmedNonblank(value, "Original file name");
  if (
    name.length > 255 || name.includes("/") || name.includes("\\") ||
    name === "." || name === ".." || name.includes("..") ||
    DANGEROUS_EXTENSION.test(name)
  ) {
    throw validationFailed("Document file name is invalid.");
  }
  const extension = extensionOf(name);
  if (!ALLOWED.has(extension)) {
    throw validationFailed("Document file extension is not allowed.");
  }
  return name;
}

function validateDeclaredMime(fileName: string, value: unknown): string {
  const mime = trimmedNonblank(value, "MIME type").toLowerCase();
  if (ALLOWED.get(extensionOf(fileName)) !== mime) {
    throw validationFailed("Document MIME type and extension do not match.");
  }
  return mime;
}

function verifiedMimeFromMagic(bytes: Uint8Array): string | null {
  if (bytes.length >= 5 && text(bytes.slice(0, 5)) === "%PDF-") {
    return "application/pdf";
  }
  if (
    bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) return "image/jpeg";
  if (
    bytes.length >= 8 && bytes[0] === 0x89 &&
    text(bytes.slice(1, 4)) === "PNG" &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) return "image/png";
  if (
    bytes.length >= 12 && text(bytes.slice(0, 4)) === "RIFF" &&
    text(bytes.slice(8, 12)) === "WEBP"
  ) return "image/webp";
  return null;
}

function extensionOf(fileName: string): string {
  const match = /\.([^.]+)$/.exec(fileName.toLowerCase());
  return match?.[1] ?? "";
}

function randomObjectToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

function text(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

async function rpc(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
  allowFailedStatus = false,
): Promise<RpcResult> {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) return result;
  if (allowFailedStatus && result.error.code === "23514") return result;
  throw mapDatabaseError(result.error);
}

async function rpcAllowUnauthorized(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
): Promise<RpcResult> {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) return result;
  if (
    typeof result.error.code === "string" &&
    AUTHZ_ERROR_CODES.has(result.error.code)
  ) {
    return result;
  }
  throw mapDatabaseError(result.error);
}

async function bestEffortRemove(
  auth: AuthenticatedContext,
  bucket: string,
  objectKey: string,
): Promise<void> {
  try {
    await serviceClient(auth).storage.from(bucket).remove([objectKey]);
  } catch {
    // Unfinalized cleanup is best effort; database invalidation remains authoritative.
  }
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

function optionalUuid(value: unknown, field: string): string | null {
  return value === undefined || value === null ? null : uuidValue(value, field);
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
    return unauthorized("Operation is not authorized.");
  }
  if (error.code === "23514" || error.code === "23505") {
    return validationFailed("Document storage request cannot be completed.");
  }
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
