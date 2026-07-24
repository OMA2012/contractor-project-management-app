import type { AppEnv } from "./env.ts";
import { loadAppEnv } from "./env.ts";
import { authenticateRequest } from "./auth.ts";
import type { AuthenticatedContext } from "./auth.ts";
import { corsHeaders, optionsResponse, requireAllowedOrigin } from "./cors.ts";
import { deniedLogArgs } from "./denied_log.ts";
import { SafeError, unauthorized, validationFailed } from "./errors.ts";
import {
  errorEnvelope,
  readJsonObject,
  requestIdFromHeaders,
  successEnvelope,
} from "./http.ts";
import { reason, rejectUnknownFields, uuidValue } from "./validation.ts";

const LONG_BAN_DURATION = "876000h";
const AUTHZ_ERROR_CODES = new Set(["42501", "PGRST301"]);

type LifecycleKind =
  | "suspend-client-account"
  | "reactivate-client-account"
  | "disable-client-account";

type LifecycleStatus = "SUSPENDED" | "ACTIVE" | "DISABLED";
type AuthUpdate = "applied" | "warning" | "compensated" | "compensation_failed";

interface RpcError {
  code?: string;
  message?: string;
}

type RpcResult = { data: unknown; error: RpcError | null };
type AuthResult = { data: unknown; error: RpcError | null };

interface RpcClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

interface AuthAdminClient {
  updateUserById(
    userId: string,
    attributes: { ban_duration: string },
  ): Promise<AuthResult>;
}

interface ServiceClient extends RpcClient {
  auth: { admin: AuthAdminClient };
}

export interface LifecycleHandlerDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
}

interface LifecycleRequest {
  clientUserId: string;
  reasonText: string;
}

interface ClientContext {
  clientUserId: string;
  authSubject: string;
  accountStatus: string;
  isActive: boolean;
}

export function createLifecycleHandler(
  kind: LifecycleKind,
  deps: LifecycleHandlerDependencies = {},
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
      const authenticated = await (deps.authenticate ?? authenticateRequest)(
        req,
        env,
      );
      const body = await readJsonObject(req);
      const data = await dispatch(kind, body, authenticated, requestId);
      return successEnvelope(data, requestId, {
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

async function dispatch(
  kind: LifecycleKind,
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  const input = lifecycleRequest(body);
  const context = await trustedClientContext(auth, input.clientUserId, kind);
  switch (kind) {
    case "suspend-client-account":
      return await databaseFirstLifecycle(auth, input, context, requestId, {
        gateway: "server_suspend_client_account",
        action: "client_account_suspend",
        status: "SUSPENDED",
        banDuration: LONG_BAN_DURATION,
        authFailureMessage:
          "Client was suspended, but Auth ban synchronization must be retried.",
      });
    case "disable-client-account":
      return await databaseFirstLifecycle(auth, input, context, requestId, {
        gateway: "server_disable_client_account",
        action: "client_account_disable",
        status: "DISABLED",
        banDuration: LONG_BAN_DURATION,
        authFailureMessage:
          "Client was disabled, but Auth ban synchronization must be retried.",
      });
    case "reactivate-client-account":
      return await reactivateLifecycle(auth, input, context, requestId);
  }
}

function lifecycleRequest(body: Record<string, unknown>): LifecycleRequest {
  rejectUnknownFields(body, ["client_user_id", "reason"]);
  return {
    clientUserId: uuidValue(body.client_user_id, "Client user ID"),
    reasonText: reason(body.reason),
  };
}

async function trustedClientContext(
  auth: AuthenticatedContext,
  clientUserId: string,
  kind: LifecycleKind,
): Promise<ClientContext> {
  const result = await rpc(auth, "server_client_identity_context", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_client_user_id: clientUserId,
  }, {
    action: actionFor(kind),
    entityType: "user",
    entityId: clientUserId,
  });
  const row = firstRow(result.data);
  const authSubject = row.auth_subject;
  const accountStatus = row.account_status;
  const isActive = row.is_active;
  if (
    typeof authSubject !== "string" ||
    typeof accountStatus !== "string" ||
    typeof isActive !== "boolean"
  ) {
    throw new SafeError(
      500,
      "internal_error",
      "Database response was invalid.",
    );
  }
  return {
    clientUserId,
    authSubject,
    accountStatus,
    isActive,
  };
}

async function databaseFirstLifecycle(
  auth: AuthenticatedContext,
  input: LifecycleRequest,
  context: ClientContext,
  requestId: string,
  operation: {
    gateway: string;
    action: string;
    status: LifecycleStatus;
    banDuration: string;
    authFailureMessage: string;
  },
): Promise<Record<string, unknown>> {
  const result = await rpc(auth, operation.gateway, {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_client_user_id: input.clientUserId,
    p_reason: input.reasonText,
    p_request_identifier: requestId,
  }, {
    action: operation.action,
    entityType: "user",
    entityId: input.clientUserId,
  });
  const clientUserId = scalarUuid(result.data);
  const banResult = await serviceClient(auth).auth.admin.updateUserById(
    context.authSubject,
    { ban_duration: operation.banDuration },
  );
  if (banResult.error) {
    return {
      client_user_id: clientUserId,
      status: operation.status,
      auth_update: "warning",
      message: operation.authFailureMessage,
    };
  }
  inspectAuthUser(banResult.data);
  return {
    client_user_id: clientUserId,
    status: operation.status,
    auth_update: "applied",
  };
}

async function reactivateLifecycle(
  auth: AuthenticatedContext,
  input: LifecycleRequest,
  context: ClientContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  if (context.accountStatus === "DISABLED") {
    throw validationFailed(
      "Client account lifecycle request cannot be completed.",
    );
  }
  const unbanResult = await serviceClient(auth).auth.admin.updateUserById(
    context.authSubject,
    { ban_duration: "none" },
  );
  if (unbanResult.error) {
    throw new SafeError(
      503,
      "internal_error",
      "Auth ban removal must be retried.",
    );
  }
  inspectAuthUser(unbanResult.data);

  const result = await serviceClient(auth).rpc(
    "server_reactivate_client_account",
    {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_client_user_id: input.clientUserId,
      p_reason: input.reasonText,
      p_request_identifier: requestId,
    },
  );
  if (!result.error) {
    return {
      client_user_id: scalarUuid(result.data),
      status: "ACTIVE",
      auth_update: "applied",
    };
  }

  if (isAuthorizationError(result.error)) {
    await recordDeniedOperation(auth, {
      action: "client_account_reactivate",
      entityType: "user",
      entityId: input.clientUserId,
    });
  }
  const compensation = await serviceClient(auth).auth.admin.updateUserById(
    context.authSubject,
    { ban_duration: LONG_BAN_DURATION },
  );
  return {
    client_user_id: input.clientUserId,
    status: "SUSPENDED",
    auth_update: compensation.error ? "compensation_failed" : "compensated",
    message: "Client was not reactivated. Database state remains suspended.",
  };
}

async function rpc(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
  denied: { action: string; entityType: string; entityId?: string },
): Promise<RpcResult> {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) {
    return result;
  }
  if (isAuthorizationError(result.error)) {
    await recordDeniedOperation(auth, denied);
  }
  throw mapDatabaseError(result.error);
}

async function recordDeniedOperation(
  auth: AuthenticatedContext,
  denied: { action: string; entityType: string; entityId?: string },
): Promise<void> {
  const args = deniedLogArgs({
    action: denied.action,
    entityType: denied.entityType,
    reasonCode: "authorization_denied",
    metadata: { source: "edge_function" },
  });
  try {
    await serviceClient(auth).rpc("server_record_denied_privileged_operation", {
      p_actor_auth_subject: auth.actorAuthSubject,
      p_action: args.action,
      p_entity_type: args.entityType,
      p_entity_id: denied.entityId ?? null,
      p_reason_code: args.reasonCode,
      p_metadata: args.metadata,
    });
  } catch {
    // Denial logging is best effort and must not replace the original denial.
  }
}

function actionFor(kind: LifecycleKind): string {
  switch (kind) {
    case "suspend-client-account":
      return "client_account_suspend";
    case "reactivate-client-account":
      return "client_account_reactivate";
    case "disable-client-account":
      return "client_account_disable";
  }
}

function serviceClient(auth: AuthenticatedContext): ServiceClient {
  return auth.serviceClient as unknown as ServiceClient;
}

function inspectAuthUser(data: unknown): void {
  if (data !== null && typeof data !== "object") {
    throw new SafeError(
      502,
      "internal_error",
      "Auth provider response was invalid.",
    );
  }
}

function firstRow(data: unknown): Record<string, unknown> {
  if (Array.isArray(data) && data.length > 0 && isRecord(data[0])) {
    return data[0];
  }
  if (isRecord(data)) {
    return data;
  }
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function scalarUuid(data: unknown): string {
  if (typeof data === "string") {
    return data;
  }
  const row = firstRow(data);
  const value = row.id ?? row.server_suspend_client_account ??
    row.server_reactivate_client_account ?? row.server_disable_client_account;
  if (typeof value === "string") {
    return value;
  }
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function mapError(error: unknown): unknown {
  if (error instanceof SafeError) {
    return error;
  }
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

function mapDatabaseError(error: RpcError): SafeError {
  if (isAuthorizationError(error)) {
    return unauthorized("Operation is not authorized.");
  }
  if (error.code === "23514" || error.code === "23505") {
    return validationFailed(
      "Client account lifecycle request cannot be completed.",
    );
  }
  return new SafeError(
    500,
    "internal_error",
    "Request could not be completed.",
  );
}

function isAuthorizationError(error: RpcError): boolean {
  return typeof error.code === "string" && AUTHZ_ERROR_CODES.has(error.code);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
