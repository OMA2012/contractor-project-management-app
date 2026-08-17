import type { AppEnv } from "../_shared/env.ts";
import { loadAppEnv } from "../_shared/env.ts";
import type { AuthenticatedContext } from "../_shared/auth.ts";
import { authenticateRequest } from "../_shared/auth.ts";
import {
  corsHeaders,
  optionsResponse,
  requireAllowedOrigin,
} from "../_shared/cors.ts";
import {
  SafeError,
  unauthorized,
  validationFailed,
} from "../_shared/errors.ts";
import {
  errorEnvelope,
  readJsonObject,
  requestIdFromHeaders,
  successEnvelope,
} from "../_shared/http.ts";
import { invitationUrl } from "../_shared/invitation_url.ts";
import {
  byteaHex,
  decodeBase64Url,
  generateInvitationToken,
  sha256Digest,
} from "../_shared/token.ts";
import {
  rejectUnknownFields,
  trimmedNonblank,
  uuidValue,
} from "../_shared/validation.ts";

type RpcError = { code?: string; message?: string };
type RpcResult = { data: unknown; error: RpcError | null };
type RpcClient = {
  rpc: (name: string, args: Record<string, unknown>) => Promise<RpcResult>;
};
type ServiceClient = RpcClient & {
  auth: {
    admin: {
      generateLink: (args: Record<string, unknown>) => Promise<RpcResult>;
      inviteUserByEmail: (
        email: string,
        options: Record<string, unknown>,
      ) => Promise<RpcResult>;
    };
  };
};

export interface ClientProjectsGatewayDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
}

const AUTHZ_CODES = new Set(["42501", "PGRST301"]);

export function createClientProjectsGateway(
  deps: ClientProjectsGatewayDependencies = {},
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
      const body = await readJsonObject(req);
      const data = await dispatch(body, auth, env, requestId);
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

if (import.meta.main) {
  Deno.serve(createClientProjectsGateway());
}

async function dispatch(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  env: AppEnv,
  requestId: string,
): Promise<Record<string, unknown>> {
  const action = trimmedNonblank(body.action, "Action");
  switch (action) {
    case "client_list":
      rejectUnknownFields(body, ["action"]);
      return { clients: await clientList(auth) };
    case "client_detail":
      rejectUnknownFields(body, ["action", "client_id"]);
      return {
        client: await clientDetail(
          auth,
          uuidValue(body.client_id, "Client ID"),
        ),
      };
    case "client_projects":
      rejectUnknownFields(body, ["action", "client_id"]);
      return {
        projects: await projectList(
          auth,
          uuidValue(body.client_id, "Client ID"),
        ),
      };
    case "client_create":
      rejectUnknownFields(body, clientFields(false));
      return {
        client: await mutateClient(
          auth,
          body,
          requestId,
          "server_create_client_record",
        ),
      };
    case "client_update":
      rejectUnknownFields(body, clientFields(true));
      return {
        client: await mutateClient(
          auth,
          body,
          requestId,
          "server_update_client_record",
        ),
      };
    case "invitation_status":
      rejectUnknownFields(body, ["action", "client_id"]);
      return {
        invitation: await invitationStatus(
          auth,
          uuidValue(body.client_id, "Client ID"),
        ),
      };
    case "invitation_send":
      rejectUnknownFields(body, ["action", "client_id"]);
      return await sendInvitation(
        auth,
        env,
        uuidValue(body.client_id, "Client ID"),
        requestId,
      );
    case "invitation_resend":
      rejectUnknownFields(body, ["action", "invited_user_id"]);
      return await resendInvitation(
        auth,
        env,
        uuidValue(body.invited_user_id, "Invited user ID"),
        requestId,
      );
    case "project_list":
      rejectUnknownFields(body, ["action"]);
      return { projects: await projectList(auth) };
    case "project_detail":
      rejectUnknownFields(body, ["action", "project_id"]);
      return {
        project: await projectDetail(
          auth,
          uuidValue(body.project_id, "Project ID"),
        ),
      };
    case "project_create":
      rejectUnknownFields(body, projectFields(false));
      return {
        project: await mutateProject(
          auth,
          body,
          requestId,
          "server_create_project_record",
        ),
      };
    case "project_update":
      rejectUnknownFields(body, projectFields(true));
      return {
        project: await mutateProject(
          auth,
          body,
          requestId,
          "server_update_project_record",
        ),
      };
    case "project_transition":
      rejectUnknownFields(body, [
        "action",
        "project_id",
        "expected_version_number",
        "new_status",
        "cancellation_reason",
      ]);
      return {
        project: await transitionProject(auth, body, requestId),
      };
    default:
      throw validationFailed("Action is not supported.");
  }
}

function clientFields(update: boolean): string[] {
  return [
    "action",
    ...(update ? ["client_id", "expected_version_number"] : []),
    "display_name",
    "legal_name",
    "email",
    "phone",
    "address",
    "internal_notes",
  ];
}

function projectFields(update: boolean): string[] {
  return [
    "action",
    ...(update ? ["project_id", "expected_version_number"] : []),
    "client_id",
    "name",
    "reporting_currency_code",
    "project_type",
    "location",
    "start_date",
    "end_date",
    "client_visible_summary",
    "internal_notes",
  ];
}

async function clientList(
  auth: AuthenticatedContext,
): Promise<Record<string, unknown>[]> {
  const clients = await rpc(auth, "server_owner_client_record_list", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_limit: 100,
    p_offset: 0,
  });
  const projects = await projectList(auth);
  return clients.map((row) => projectClient(row, projects));
}

async function clientDetail(
  auth: AuthenticatedContext,
  clientId: string,
): Promise<Record<string, unknown>> {
  const row = first(
    await rpc(auth, "server_owner_client_record_detail", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_client_id: clientId,
    }),
  );
  return projectClient(row, await projectList(auth, clientId));
}

function projectClient(
  row: Record<string, unknown>,
  projects: Record<string, unknown>[],
) {
  return {
    id: row.id,
    client_number: row.client_number,
    display_name: row.display_name,
    legal_name: row.legal_name,
    email: row.email,
    phone: row.phone,
    address: row.address,
    status: row.status,
    is_active: row.is_active,
    portal_user_id: row.portal_user_id,
    version_number: row.version_number,
    project_count:
      projects.filter((project) => project.client_id === row.id).length,
  };
}

async function mutateClient(
  auth: AuthenticatedContext,
  body: Record<string, unknown>,
  requestId: string,
  name: string,
): Promise<Record<string, unknown>> {
  const isUpdate = name === "server_update_client_record";
  const result = first(
    await rpc(auth, name, {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      ...(isUpdate
        ? {
          p_client_id: uuidValue(body.client_id, "Client ID"),
          p_expected_version_number: positiveInt(
            body.expected_version_number,
            "Version",
          ),
        }
        : {}),
      p_display_name: trimmedNonblank(body.display_name, "Client name"),
      p_legal_name: optionalText(body.legal_name),
      p_email: optionalText(body.email),
      p_phone: optionalText(body.phone),
      p_address: optionalText(body.address),
      p_internal_notes: optionalText(body.internal_notes),
      p_request_identifier: requestId,
    }),
  );
  return await clientDetail(auth, String(result.client_id));
}

async function invitationStatus(auth: AuthenticatedContext, clientId: string) {
  const client = await clientDetail(auth, clientId);
  const linkedInvitation = await rpc(
    auth,
    "server_owner_client_invitation_status",
    {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_client_id: clientId,
    },
  );
  if (linkedInvitation.length > 0) return first(linkedInvitation);
  const portalUserId = client.portal_user_id;
  if (typeof portalUserId !== "string") {
    return { status: "NOT_SENT" };
  }
  const rows = await rpc(auth, "server_client_identity_context", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_client_user_id: portalUserId,
  });
  const row = first(rows);
  return {
    invited_user_id: portalUserId,
    status: row.latest_invitation_status ?? row.account_status,
    expires_at: row.latest_invitation_expires_at,
  };
}

async function sendInvitation(
  auth: AuthenticatedContext,
  env: AppEnv,
  clientId: string,
  requestId: string,
): Promise<Record<string, unknown>> {
  const client = await clientDetail(auth, clientId);
  const email = String(client.email ?? "").trim().toLowerCase();
  if (!email) throw validationFailed("Client email is required.");
  const token = generateInvitationToken();
  const redirectTo = invitationUrl(env.appBaseUrl, token).toString();
  const service = serviceClient(auth);
  const linkResult = await service.auth.admin.generateLink({
    type: "invite",
    email,
    options: { redirectTo },
  });
  if (linkResult.error) {
    throw new SafeError(
      503,
      "internal_error",
      "Invitation could not be prepared.",
    );
  }
  const invitedAuthSubject = extractAuthUserId(linkResult.data);
  const digest = await sha256Digest(decodeBase64Url(token));
  const row = first(
    await rpc(auth, "server_create_client_record_invitation", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_client_id: clientId,
      p_invited_auth_subject: invitedAuthSubject,
      p_token_hash: byteaHex(digest),
      p_request_identifier: requestId,
    }),
  );
  const inviteResult = await service.auth.admin.inviteUserByEmail(email, {
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
    invitation: {
      invited_user_id: row.invited_user_id,
      invitation_id: row.invitation_id,
      expires_at: row.expires_at,
      status: "PENDING",
    },
  };
}

async function resendInvitation(
  auth: AuthenticatedContext,
  env: AppEnv,
  invitedUserId: string,
  requestId: string,
) {
  const context = first(
    await rpc(auth, "server_client_identity_context", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_client_user_id: invitedUserId,
    }),
  );
  if (
    context.account_status !== "INVITED" ||
    context.latest_invitation_status === "ACCEPTED"
  ) {
    throw validationFailed("Invitation cannot be resent.");
  }
  const email = String(context.normalized_email ?? "").trim().toLowerCase();
  const token = generateInvitationToken();
  const redirectTo = invitationUrl(env.appBaseUrl, token).toString();
  const service = serviceClient(auth);
  const link = await service.auth.admin.generateLink({
    type: "invite",
    email,
    options: { redirectTo },
  });
  if (link.error) {
    throw new SafeError(
      503,
      "internal_error",
      "Invitation could not be prepared.",
    );
  }
  const digest = await sha256Digest(decodeBase64Url(token));
  const row = first(
    await rpc(auth, "server_resend_client_invitation", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_invited_user_id: invitedUserId,
      p_token_hash: byteaHex(digest),
      p_request_identifier: requestId,
    }),
  );
  const sent = await service.auth.admin.inviteUserByEmail(email, {
    redirectTo,
  });
  if (sent.error) {
    throw new SafeError(
      503,
      "internal_error",
      "Invitation email could not be sent. Retry resend.",
    );
  }
  return { invitation: { ...row, status: "PENDING" } };
}

async function projectList(auth: AuthenticatedContext, clientId?: string) {
  const rows = await rpc(auth, "server_owner_project_record_list", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_limit: 100,
    p_offset: 0,
  });
  const clients = await rpc(auth, "server_owner_client_record_list", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_limit: 100,
    p_offset: 0,
  });
  return rows
    .filter((row) => !clientId || row.client_id === clientId)
    .map((row) => projectProjection(row, clients));
}

async function projectDetail(auth: AuthenticatedContext, projectId: string) {
  const row = first(
    await rpc(auth, "server_owner_project_record_detail", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_project_id: projectId,
    }),
  );
  const clients = await rpc(auth, "server_owner_client_record_list", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_limit: 100,
    p_offset: 0,
  });
  return projectProjection(row, clients);
}

function projectProjection(
  row: Record<string, unknown>,
  clients: Record<string, unknown>[],
) {
  const client = clients.find((candidate) => candidate.id === row.client_id);
  return {
    id: row.id,
    client_id: row.client_id,
    client_number: client?.client_number,
    client_name: client?.display_name,
    project_number: row.project_number,
    name: row.name,
    project_type: row.project_type,
    location: row.location,
    status: row.status,
    start_date: row.start_date,
    end_date: row.end_date,
    reporting_currency_code: row.reporting_currency_code,
    client_visible_summary: row.client_visible_summary,
    internal_notes: row.internal_notes,
    version_number: row.version_number,
  };
}

async function mutateProject(
  auth: AuthenticatedContext,
  body: Record<string, unknown>,
  requestId: string,
  name: string,
) {
  const isUpdate = name === "server_update_project_record";
  const result = first(
    await rpc(auth, name, {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      ...(isUpdate
        ? {
          p_project_id: uuidValue(body.project_id, "Project ID"),
          p_expected_version_number: positiveInt(
            body.expected_version_number,
            "Version",
          ),
        }
        : {}),
      p_client_id: uuidValue(body.client_id, "Client ID"),
      p_name: trimmedNonblank(body.name, "Project name"),
      p_reporting_currency_code: currency(body.reporting_currency_code),
      p_project_type: optionalText(body.project_type),
      p_location: optionalText(body.location),
      p_start_date: optionalText(body.start_date),
      p_end_date: optionalText(body.end_date),
      p_client_visible_summary: optionalText(body.client_visible_summary),
      p_internal_notes: optionalText(body.internal_notes),
      p_request_identifier: requestId,
    }),
  );
  return await projectDetail(auth, String(result.project_id));
}

async function transitionProject(
  auth: AuthenticatedContext,
  body: Record<string, unknown>,
  requestId: string,
) {
  const status = trimmedNonblank(body.new_status, "Status");
  const projectId = uuidValue(body.project_id, "Project ID");
  const version = positiveInt(body.expected_version_number, "Version");
  const name = status === "COMPLETED"
    ? "server_complete_project_record"
    : status === "CANCELLED"
    ? "server_cancel_project_record"
    : status === "ARCHIVED"
    ? "server_archive_project_record"
    : "server_change_project_status";
  await rpc(auth, name, {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_project_id: projectId,
    p_expected_version_number: version,
    ...(status === "CANCELLED"
      ? {
        p_cancellation_reason: trimmedNonblank(
          body.cancellation_reason,
          "Reason",
        ),
      }
      : status === "COMPLETED" || status === "ARCHIVED"
      ? {}
      : { p_new_status: status }),
    p_request_identifier: requestId,
  });
  return await projectDetail(auth, projectId);
}

async function rpc(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
) {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) {
    if (Array.isArray(result.data)) {
      return result.data as Record<string, unknown>[];
    }
    if (result.data && typeof result.data === "object") {
      return [result.data as Record<string, unknown>];
    }
    return [];
  }
  if (result.error.code && AUTHZ_CODES.has(result.error.code)) {
    throw unauthorized("Operation is not authorized.");
  }
  if (
    result.error.code === "23514" || result.error.code === "23505" ||
    result.error.code === "40001"
  ) {
    throw validationFailed("Owner Client/Project request cannot be completed.");
  }
  throw new SafeError(500, "internal_error", "Request could not be completed.");
}

function first(rows: Record<string, unknown>[]) {
  if (rows.length === 0) throw validationFailed("Record was not found.");
  return rows[0];
}

function serviceClient(auth: AuthenticatedContext): ServiceClient {
  return auth.serviceClient as unknown as ServiceClient;
}

function optionalText(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function positiveInt(value: unknown, field: string) {
  if (typeof value === "number" && Number.isInteger(value) && value > 0) {
    return value;
  }
  throw validationFailed(`${field} is invalid.`);
}

function currency(value: unknown) {
  const code = trimmedNonblank(value, "Reporting currency").toUpperCase();
  if (!/^[A-Z]{3}$/.test(code)) {
    throw validationFailed("Reporting currency is invalid.");
  }
  return code;
}

function extractAuthUserId(data: unknown): string {
  if (data && typeof data === "object") {
    const user = (data as { user?: { id?: unknown } }).user;
    if (typeof user?.id === "string") return user.id;
  }
  throw new SafeError(
    502,
    "internal_error",
    "Auth provider response was invalid.",
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
