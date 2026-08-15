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
  "queue",
] as const;
type Action = typeof ACTIONS[number];
type RpcError = { code?: string; message?: string };
type RpcResult = { data: unknown; error: RpcError | null };
interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

export function createOpeningBalanceHandler(deps: {
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
  const action = actionValue(body.action);
  switch (action) {
    case "list":
      return { opening_balances: await list(body, auth) };
    case "detail":
      return { opening_balance: await detail(body, auth) };
    case "create":
      return { opening_balance: await create(body, auth, requestId) };
    case "update":
      return { opening_balance: await update(body, auth, requestId) };
    case "submit":
      return {
        opening_balance: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_opening_balance",
        ),
      };
    case "approve":
      return {
        opening_balance: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_opening_balance",
        ),
      };
    case "reject":
      return { opening_balance: await reject(body, auth, requestId) };
    case "queue":
      return { items: await queue(body, auth) };
  }
}

function actionValue(value: unknown): Action {
  if (
    typeof value === "string" && (ACTIONS as readonly string[]).includes(value)
  ) return value as Action;
  throw validationFailed("Opening balance action is unsupported.");
}

async function list(body: Record<string, unknown>, auth: AuthenticatedContext) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_opening_balance_list", base(auth, body)))
      .data,
  ).map(summary);
}

async function detail(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "financial_event_id"]);
  return detailRow(
    firstRow(
      (await rpc(auth, "server_owner_opening_balance_detail", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
      })).data,
    ),
  );
}

async function queue(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "section", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_financial_approval_queue", {
      ...base(auth, body),
      p_section: section(body.section),
    })).data,
  ).map(queueRow);
}

async function create(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_account_id",
    "amount",
    "opening_date",
    "reporting_currency_code",
    "description",
    "notes",
    "duplicate_fingerprint",
  ]);
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_create_opening_balance", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_financial_account_id: uuidValue(
          body.financial_account_id,
          "Financial account ID",
        ),
        p_amount: decimal(body.amount, "Amount"),
        p_opening_date: dateValue(body.opening_date, "Opening date"),
        p_reporting_currency_code: currency(body.reporting_currency_code),
        p_description: optional(body.description, "Description"),
        p_notes: optional(body.notes, "Notes"),
        p_duplicate_fingerprint: optional(
          body.duplicate_fingerprint,
          "Duplicate fingerprint",
        ),
        p_request_identifier: requestId,
      })).data,
    ),
  );
}

async function update(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_event_id",
    "expected_version_number",
    "amount",
    "opening_date",
    "reporting_currency_code",
    "description",
    "notes",
  ]);
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_update_opening_balance", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
        p_amount: decimal(body.amount, "Amount"),
        p_opening_date: dateValue(body.opening_date, "Opening date"),
        p_reporting_currency_code: currency(body.reporting_currency_code),
        p_description: optional(body.description, "Description"),
        p_notes: optional(body.notes, "Notes"),
        p_request_identifier: requestId,
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

async function reject(
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
      (await rpc(auth, "server_owner_reject_opening_balance", {
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

const base = (auth: AuthenticatedContext, body: Record<string, unknown>) => ({
  p_verified_owner_auth_subject: auth.actorAuthSubject,
  p_limit: bounded(body.limit, 50, 1, 100),
  p_offset: bounded(body.offset, 0, 0, 1_000_000),
});
const summary = (r: Record<string, unknown>) => ({
  ...money(r),
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  financial_account_id: str(r, "financial_account_id"),
  opening_date: str(r, "opening_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  version_number: int(r.version_number),
});
const detailRow = (r: Record<string, unknown>) => ({
  ...summary(r),
  reporting_currency_code: str(r, "reporting_currency_code"),
  description: nullable(r.description),
  notes: nullable(r.notes),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
});
const queueRow = (r: Record<string, unknown>) => ({
  ...money(r),
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  event_type: str(r, "event_type"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  related_label: str(r, "related_label"),
  event_date: str(r, "event_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  created_by_me: bool(r.created_by_me),
  eligible_for_my_approval: bool(r.eligible_for_my_approval),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
  version_number: int(r.version_number),
});
const mutation = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  financial_transaction_id: nullable(r.financial_transaction_id),
  event_number: nullable(r.event_number),
  transaction_number: nullable(r.transaction_number),
  status: nullable(r.status ?? r.event_status),
  transaction_status: nullable(r.transaction_status),
  ledger_entry_count: typeof r.ledger_entry_count === "number"
    ? r.ledger_entry_count
    : null,
  version_number: int(r.version_number),
});
const money = (r: Record<string, unknown>) => ({
  amount: decOut(r.amount),
  currency_code: str(r, "currency_code"),
});
function rows(data: unknown): Record<string, unknown>[] {
  if (Array.isArray(data) && data.every(isRecord)) return data;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function firstRow(data: unknown) {
  const all = rows(data);
  if (all[0]) return all[0];
  throw validationFailed("Opening balance was not found.");
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
function bool(v: unknown) {
  if (typeof v === "boolean") return v;
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
  return bounded(v, 0, 1, 2_147_483_647);
}
function section(v: unknown) {
  if (v === undefined) return "eligible";
  if (
    typeof v === "string" &&
    ["eligible", "created_by_me", "recent", "rejected"].includes(v)
  ) return v;
  throw validationFailed("Approval queue section is invalid.");
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
    return validationFailed("Opening balance version conflict.");
  }
  if (["23514", "23505", "22P02"].includes(error.code ?? "")) {
    return validationFailed(
      error.message ?? "Opening balance request cannot be completed.",
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
