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
import { invitationUrl } from "./invitation_url.ts";
import {
  byteaHex,
  decodeBase64Url,
  generateInvitationToken,
  sha256Digest,
} from "./token.ts";
import {
  fullName,
  normalizedEmail,
  reason,
  rejectUnknownFields,
  uuidValue,
} from "./validation.ts";

type RpcResult = { data: unknown; error: RpcError | null };
type AuthResult = { data: unknown; error: RpcError | null };

interface RpcError {
  code?: string;
  message?: string;
}

interface RpcClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

interface AuthAdminClient {
  generateLink(args: Record<string, unknown>): Promise<AuthResult>;
  inviteUserByEmail(
    email: string,
    options: Record<string, unknown>,
  ): Promise<AuthResult>;
}

interface ServiceClient extends RpcClient {
  auth: { admin: AuthAdminClient };
}

export interface HandlerDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
}

type HandlerKind =
  | "create-client-invitation"
  | "resend-client-invitation"
  | "revoke-client-invitation"
  | "accept-client-invitation";

const AUTHZ_ERROR_CODES = new Set(["42501", "PGRST301"]);

export function createInvitationHandler(
  kind: HandlerKind,
  deps: HandlerDependencies = {},
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
      const data = await dispatch(kind, body, authenticated, env, requestId);
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
  kind: HandlerKind,
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  env: AppEnv,
  requestId: string,
): Promise<Record<string, unknown>> {
  switch (kind) {
    case "create-client-invitation":
      return await createClientInvitation(body, auth, env, requestId);
    case "resend-client-invitation":
      return await resendClientInvitation(body, auth, env, requestId);
    case "revoke-client-invitation":
      return await revokeClientInvitation(body, auth, requestId);
    case "accept-client-invitation":
      return await acceptClientInvitation(body, auth, requestId);
  }
}

async function createClientInvitation(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  env: AppEnv,
  requestId: string,
): Promise<Record<string, unknown>> {
  rejectUnknownFields(body, ["email"]);
  const email = normalizedEmail(body.email);
  const token = generateInvitationToken();
  const redirectTo = invitationUrl(env.appBaseUrl, token).toString();
  const authAdmin = serviceClient(auth).auth.admin;
  const linkResult = await authAdmin.generateLink({
    type: "invite",
    email,
    options: { redirectTo },
  });
  assertNoAuthError(linkResult);
  const invitedAuthSubject = extractAuthUserId(linkResult.data);
  const digest = await sha256Digest(decodeBase64Url(token));
  const createResult = await rpc(auth, "server_create_client_invitation", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_invited_auth_subject: invitedAuthSubject,
    p_normalized_email: email,
    p_token_hash: byteaHex(digest),
    p_request_identifier: requestId,
  }, {
    action: "client_invitation_create",
    entityType: "user",
  });
  const row = firstRow(createResult.data);
  const inviteResult = await authAdmin.inviteUserByEmail(email, {
    redirectTo,
  });
  if (inviteResult.error) {
    throw new SafeError(
      503,
      "internal_error",
      "Invitation email could not be sent. Retry resend.",
    );
  }
  return {
    invited_user_id: row.invited_user_id,
    invitation_id: row.invitation_id,
    expires_at: row.expires_at,
    status: "PENDING",
  };
}

async function resendClientInvitation(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  env: AppEnv,
  requestId: string,
): Promise<Record<string, unknown>> {
  rejectUnknownFields(body, ["invited_user_id"]);
  const invitedUserId = uuidValue(body.invited_user_id, "Invited user ID");
  const contextResult = await rpc(auth, "server_client_identity_context", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_client_user_id: invitedUserId,
  }, {
    action: "client_invitation_resend",
    entityType: "user",
    entityId: invitedUserId,
  });
  const context = firstRow(contextResult.data);
  if (
    context.account_status !== "INVITED" ||
    context.is_active !== false ||
    context.latest_invitation_status === "ACCEPTED"
  ) {
    throw validationFailed("Invitation cannot be resent.");
  }
  const email = normalizedEmail(context.normalized_email);
  const token = generateInvitationToken();
  const redirectTo = invitationUrl(env.appBaseUrl, token).toString();
  const authAdmin = serviceClient(auth).auth.admin;
  const linkResult = await authAdmin.generateLink({
    type: "invite",
    email,
    options: { redirectTo },
  });
  assertNoAuthError(linkResult);
  const digest = await sha256Digest(decodeBase64Url(token));
  const resendResult = await rpc(auth, "server_resend_client_invitation", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_invited_user_id: invitedUserId,
    p_token_hash: byteaHex(digest),
    p_request_identifier: requestId,
  }, {
    action: "client_invitation_resend",
    entityType: "user",
    entityId: invitedUserId,
  });
  const row = firstRow(resendResult.data);
  const inviteResult = await authAdmin.inviteUserByEmail(email, {
    redirectTo,
  });
  if (inviteResult.error) {
    throw new SafeError(
      503,
      "internal_error",
      "Invitation email could not be sent. Retry resend.",
    );
  }
  return {
    invitation_id: row.invitation_id,
    resent_from_invitation_id: row.resent_from_invitation_id,
    expires_at: row.expires_at,
    status: "PENDING",
  };
}

async function revokeClientInvitation(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  rejectUnknownFields(body, ["invitation_id", "revoke_reason"]);
  const invitationId = uuidValue(body.invitation_id, "Invitation ID");
  const revokeReason = reason(body.revoke_reason);
  const revokeResult = await rpc(auth, "server_revoke_client_invitation", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_invitation_id: invitationId,
    p_revoke_reason: revokeReason,
    p_request_identifier: requestId,
  }, {
    action: "client_invitation_revoke",
    entityType: "user_invitation",
    entityId: invitationId,
  });
  return {
    invitation_id: scalarUuid(revokeResult.data),
    status: "REVOKED",
  };
}

async function acceptClientInvitation(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  rejectUnknownFields(body, ["token", "full_name"]);
  const token = typeof body.token === "string" ? body.token : "";
  const digest = await sha256Digest(decodeBase64Url(token));
  const name = fullName(body.full_name);
  const acceptResult = await rpc(auth, "server_accept_client_invitation", {
    p_verified_invited_auth_subject: auth.actorAuthSubject,
    p_token_hash: byteaHex(digest),
    p_full_name: name,
    p_request_identifier: requestId,
  }, {
    action: "client_invitation_accept",
    entityType: "user_invitation",
  });
  return {
    client_user_id: scalarUuid(acceptResult.data),
    status: "ACTIVE",
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
  await serviceClient(auth).rpc("server_record_denied_privileged_operation", {
    p_actor_auth_subject: auth.actorAuthSubject,
    p_action: args.action,
    p_entity_type: args.entityType,
    p_entity_id: denied.entityId ?? null,
    p_reason_code: args.reasonCode,
    p_metadata: args.metadata,
  });
}

function serviceClient(auth: AuthenticatedContext): ServiceClient {
  return auth.serviceClient as unknown as ServiceClient;
}

function assertNoAuthError(result: AuthResult): void {
  if (result.error) {
    throw new SafeError(
      502,
      "internal_error",
      "Invitation provider request failed.",
    );
  }
}

function extractAuthUserId(data: unknown): string {
  const user = valueAt(data, ["user"]);
  const id = typeof user === "object" && user !== null
    ? (user as Record<string, unknown>).id
    : undefined;
  if (typeof id !== "string" || !id) {
    throw new SafeError(
      502,
      "internal_error",
      "Invitation provider response was invalid.",
    );
  }
  return id;
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
  const value = row.id ?? row.server_revoke_client_invitation ??
    row.server_accept_client_invitation;
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
    return validationFailed("Invitation request cannot be completed.");
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

function valueAt(data: unknown, path: readonly string[]): unknown {
  let current = data;
  for (const part of path) {
    if (!isRecord(current)) {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
