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
import {
  rejectUnknownFields,
  trimmedNonblank,
  uuidValue,
} from "./validation.ts";

const ACTIONS = [
  "list",
  "detail",
  "create",
  "update",
  "submit",
  "approve",
  "reject",
] as const;
type Action = typeof ACTIONS[number];
type RpcError = { code?: string; message?: string };
type RpcResult = { data: unknown; error: RpcError | null };
interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

export function createAccountTransferHandler(deps: {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
} = {}) {
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
      return successEnvelope(await dispatch(body, auth, requestId), requestId, {
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
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  switch (actionValue(body.action)) {
    case "list":
      return { account_transfers: await list(body, auth) };
    case "detail":
      return { account_transfer: await detail(body, auth) };
    case "create":
      return { account_transfer: await create(body, auth, requestId) };
    case "update":
      return { account_transfer: await update(body, auth, requestId) };
    case "submit":
      return {
        account_transfer: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_account_transfer",
        ),
      };
    case "approve":
      return {
        account_transfer: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_account_transfer",
        ),
      };
    case "reject":
      return { account_transfer: await rejectTransfer(body, auth, requestId) };
  }
}

function actionValue(value: unknown): Action {
  if (
    typeof value === "string" && (ACTIONS as readonly string[]).includes(value)
  ) return value as Action;
  throw validationFailed("Account transfer action is unsupported.");
}

async function list(body: Record<string, unknown>, auth: AuthenticatedContext) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_account_transfer_list", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_limit: bounded(body.limit, 50, 1, 100),
      p_offset: bounded(body.offset, 0, 0, 1000000),
    })).data,
  ).map(summary);
}

async function detail(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "financial_event_id"]);
  return detailRow(
    firstRow(
      (await rpc(auth, "server_owner_account_transfer_detail", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
      })).data,
    ),
  );
}

async function create(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, draftFields("action"));
  return mutation(
    firstRow(
      (await rpc(
        auth,
        "server_owner_create_account_transfer",
        draftArgs(body, auth, requestId),
      )).data,
    ),
  );
}

async function update(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(
    body,
    draftFields("action", "financial_event_id", "expected_version_number"),
  );
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_update_account_transfer", {
        ...draftArgs(body, auth, requestId),
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
      })).data,
    ),
  );
}

async function transition(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
  name: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_event_id",
    "expected_version_number",
  ]);
  return mutation(firstRow(
    (await rpc(auth, name, {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_financial_event_id: uuidValue(
        body.financial_event_id,
        "Financial event ID",
      ),
      p_expected_version_number: version(body.expected_version_number),
      p_request_identifier: requestId,
    })).data,
  ));
}

async function rejectTransfer(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_event_id",
    "expected_version_number",
    "rejection_reason",
  ]);
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_reject_account_transfer", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
        p_rejection_reason: trimmedNonblank(
          body.rejection_reason,
          "Rejection reason",
        ),
        p_request_identifier: requestId,
      })).data,
    ),
  );
}

function draftFields(...extra: string[]) {
  return [
    ...extra,
    "source_account_id",
    "destination_account_id",
    "amount",
    "currency_code",
    "transfer_date",
    "reference",
    "notes",
  ];
}
function draftArgs(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  return {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_source_account_id: uuidValue(body.source_account_id, "Source account ID"),
    p_destination_account_id: uuidValue(
      body.destination_account_id,
      "Destination account ID",
    ),
    p_amount: decimal(body.amount, "Amount"),
    p_currency_code: currency(body.currency_code),
    p_transfer_date: dateValue(body.transfer_date, "Transfer date"),
    p_reference: optional(body.reference, "Reference"),
    p_notes: optional(body.notes, "Notes"),
    p_request_identifier: requestId,
  };
}
async function rpc(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
) {
  const result = await (auth.serviceClient as unknown as ServiceClient).rpc(
    name,
    args,
  );
  if (!result.error) return result;
  throw mapDatabaseError(result.error);
}
const summary = (r: Record<string, unknown>) => ({
  account_transfer_id: str(r, "account_transfer_id"),
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  source_account_id: str(r, "source_account_id"),
  destination_account_id: str(r, "destination_account_id"),
  amount: decOut(r.amount),
  currency_code: str(r, "currency_code"),
  transfer_date: str(r, "transfer_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  version_number: int(r.version_number),
});
const detailRow = (r: Record<string, unknown>) => ({
  ...summary(r),
  reference: nullable(r.reference),
  notes: nullable(r.notes),
  reporting_currency_code: nullable(r.reporting_currency_code),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
});
const mutation = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  financial_transaction_id: nullable(r.financial_transaction_id),
  account_transfer_id: nullable(r.account_transfer_id),
  event_number: nullable(r.event_number),
  transaction_number: nullable(r.transaction_number),
  status: nullable(r.status ?? r.event_status),
  transaction_status: nullable(r.transaction_status),
  ledger_entry_count: typeof r.ledger_entry_count === "number"
    ? r.ledger_entry_count
    : null,
  version_number: int(r.version_number),
});
function rows(data: unknown): Record<string, unknown>[] {
  if (Array.isArray(data) && data.every(isRecord)) return data;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function firstRow(data: unknown) {
  const all = rows(data);
  if (all[0]) return all[0];
  throw validationFailed("Account transfer was not found.");
}
function str(r: Record<string, unknown>, n: string) {
  if (typeof r[n] === "string" && r[n] !== "") return r[n];
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function nullable(v: unknown) {
  if (v === null || v === undefined) return null;
  if (typeof v === "string") return v;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function int(v: unknown) {
  if (typeof v === "number" && Number.isInteger(v)) return v;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function decimal(v: unknown, field: string) {
  if (typeof v === "string" && /^\d+(\.\d+)?$/.test(v)) return v;
  throw validationFailed(`${field} is invalid.`);
}
function decOut(v: unknown) {
  if (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v)) return v;
  if (typeof v === "number") return String(v);
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function dateValue(v: unknown, field: string) {
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  throw validationFailed(`${field} is invalid.`);
}
function currency(v: unknown) {
  if (typeof v === "string" && /^[A-Z]{3}$/.test(v)) return v;
  throw validationFailed("Currency code is invalid.");
}
function optional(v: unknown, field: string) {
  return v === undefined || v === null || v === ""
    ? null
    : trimmedNonblank(v, field);
}
function bounded(v: unknown, fallback: number, min: number, max: number) {
  const x = v ?? fallback;
  if (typeof x === "number" && Number.isInteger(x) && x >= min && x <= max) {
    return x;
  }
  throw validationFailed("Pagination is invalid.");
}
function version(v: unknown) {
  return bounded(v, 0, 1, 2147483647);
}
function mapError(error: unknown) {
  return error instanceof SafeError
    ? error
    : new SafeError(500, "internal_error", "Request could not be completed.");
}
function mapDatabaseError(error: RpcError) {
  if (error.code === "42501" || error.code === "PGRST301") {
    return unauthorized("Operation is not authorized.");
  }
  if (error.code === "40001") {
    return validationFailed("Account transfer version conflict.");
  }
  if (["23514", "23505", "22P02"].includes(error.code ?? "")) {
    return validationFailed(
      error.message ?? "Account transfer request cannot be completed.",
    );
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
