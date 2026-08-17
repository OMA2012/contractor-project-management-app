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
  "lookup",
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

export function createProjectExpenseHandler(deps: {
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
      return { project_expenses: await list(body, auth) };
    case "detail":
      return { project_expense: await detail(body, auth) };
    case "lookup":
      return {
        expense_categories: await categoryLookup(body, auth),
        projects: await projectLookup(body, auth),
      };
    case "create":
      return { project_expense: await create(body, auth, requestId) };
    case "update":
      return { project_expense: await update(body, auth, requestId) };
    case "submit":
      return {
        project_expense: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_project_expense",
        ),
      };
    case "approve":
      return {
        project_expense: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_project_expense",
        ),
      };
    case "reject":
      return { project_expense: await rejectExpense(body, auth, requestId) };
  }
}

async function categoryLookup(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_expense_category_picker_list", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_limit: bounded(body.limit, 100, 1, 100),
      p_offset: bounded(body.offset, 0, 0, 1000000),
    })).data,
  ).map(categoryRow);
}

async function projectLookup(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  return rows(
    (await rpc(auth, "server_owner_project_record_list", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_limit: bounded(body.limit, 100, 1, 100),
      p_offset: bounded(body.offset, 0, 0, 1000000),
    })).data,
  ).map(projectRow);
}

function actionValue(value: unknown): Action {
  if (
    typeof value === "string" && (ACTIONS as readonly string[]).includes(value)
  ) return value as Action;
  throw validationFailed("Project expense action is unsupported.");
}

async function list(body: Record<string, unknown>, auth: AuthenticatedContext) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_project_expense_list", base(auth, body)))
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
      (await rpc(auth, "server_owner_project_expense_detail", {
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
        "server_owner_create_project_expense",
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
      (await rpc(auth, "server_owner_update_project_expense", {
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

async function rejectExpense(
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
      (await rpc(auth, "server_owner_reject_project_expense", {
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
    "project_id",
    "expense_category_id",
    "amount",
    "currency_code",
    "paid_from_account_id",
    "expense_date",
    "vendor_name",
    "vendor_reference",
    "description",
    "private_notes",
  ];
}
function draftArgs(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  return {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_project_id: uuidValue(body.project_id, "Project ID"),
    p_expense_category_id: uuidValue(
      body.expense_category_id,
      "Expense category ID",
    ),
    p_amount: decimal(body.amount, "Amount"),
    p_currency_code: currency(body.currency_code),
    p_paid_from_account_id: uuidValue(
      body.paid_from_account_id,
      "Paid from account ID",
    ),
    p_expense_date: dateValue(body.expense_date, "Expense date"),
    p_vendor_name: optional(body.vendor_name, "Vendor"),
    p_vendor_reference: optional(body.vendor_reference, "Reference"),
    p_description: trimmedNonblank(body.description, "Description"),
    p_private_notes: optional(body.private_notes, "Private notes"),
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
const base = (auth: AuthenticatedContext, body: Record<string, unknown>) => ({
  p_verified_owner_auth_subject: auth.actorAuthSubject,
  p_limit: bounded(body.limit, 50, 1, 100),
  p_offset: bounded(body.offset, 0, 0, 1000000),
});
const summary = (r: Record<string, unknown>) => ({
  project_expense_id: str(r, "project_expense_id"),
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  expense_number: str(r, "expense_number"),
  project_id: str(r, "project_id"),
  project_number: nullable(r.project_number),
  project_name: nullable(r.project_name ?? r.name),
  client_number: nullable(r.client_number),
  client_name: nullable(r.client_name),
  expense_category_id: str(r, "expense_category_id"),
  amount: decOut(r.amount),
  currency_code: str(r, "currency_code"),
  paid_from_account_id: str(r, "paid_from_account_id"),
  expense_date: str(r, "expense_date"),
  vendor_reference: nullable(r.vendor_reference),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  version_number: int(r.version_number),
});
const detailRow = (r: Record<string, unknown>) => ({
  ...summary(r),
  vendor_name: nullable(r.vendor_name),
  description: str(r, "description"),
  private_notes: nullable(r.private_notes),
  reporting_currency_code: str(r, "reporting_currency_code"),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
});
const categoryRow = (r: Record<string, unknown>) => ({
  expense_category_id: str(r, "id"),
  code: str(r, "code"),
  name: str(r, "name"),
});
const projectRow = (r: Record<string, unknown>) => ({
  project_id: str(r, "id"),
  project_number: str(r, "project_number"),
  name: str(r, "name"),
});
const mutation = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  financial_transaction_id: nullable(r.financial_transaction_id),
  project_expense_id: nullable(r.project_expense_id),
  event_number: nullable(r.event_number),
  transaction_number: nullable(r.transaction_number),
  expense_number: nullable(r.expense_number),
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
  throw validationFailed("Project expense was not found.");
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
    return validationFailed("Project expense version conflict.");
  }
  if (["23514", "23505", "22P02"].includes(error.code ?? "")) {
    return validationFailed(
      error.message ?? "Project expense request cannot be completed.",
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
