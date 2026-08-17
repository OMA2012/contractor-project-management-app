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
  "eligible_sources",
  "reversal_list",
  "reversal_detail",
  "create_reversal",
  "submit_reversal",
  "approve_reversal",
  "reject_reversal",
  "adjustment_list",
  "adjustment_detail",
  "create_adjustment",
  "update_adjustment",
  "submit_adjustment",
  "approve_adjustment",
  "reject_adjustment",
] as const;
type Action = typeof ACTIONS[number];
type RpcError = { code?: string; message?: string };
type RpcResult = { data: unknown; error: RpcError | null };
interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

export function createFinancialCorrectionsHandler(deps: {
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
    case "eligible_sources":
      return { sources: await eligibleSources(body, auth) };
    case "reversal_list":
      return {
        reversals: await list(
          body,
          auth,
          "server_owner_reversal_list",
          reversalSummary,
        ),
      };
    case "reversal_detail":
      return {
        reversal: reversalDetail(
          firstRow(
            (await rpc(
              auth,
              "server_owner_reversal_detail",
              eventArgs(body, auth),
            )).data,
          ),
        ),
      };
    case "create_reversal":
      return { reversal: await createReversal(body, auth, requestId) };
    case "submit_reversal":
      return {
        reversal: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_reversal",
        ),
      };
    case "approve_reversal":
      return {
        reversal: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_reversal",
        ),
      };
    case "reject_reversal":
      return {
        reversal: await reject(
          body,
          auth,
          requestId,
          "server_owner_reject_reversal",
        ),
      };
    case "adjustment_list":
      return {
        adjustments: await list(
          body,
          auth,
          "server_owner_adjustment_list",
          adjustmentSummary,
        ),
      };
    case "adjustment_detail":
      return {
        adjustment: adjustmentDetail(
          firstRow(
            (await rpc(
              auth,
              "server_owner_adjustment_detail",
              eventArgs(body, auth),
            )).data,
          ),
        ),
      };
    case "create_adjustment":
      return {
        adjustment: await createAdjustment(body, auth, requestId, false),
      };
    case "update_adjustment":
      return {
        adjustment: await createAdjustment(body, auth, requestId, true),
      };
    case "submit_adjustment":
      return {
        adjustment: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_adjustment",
        ),
      };
    case "approve_adjustment":
      return {
        adjustment: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_adjustment",
        ),
      };
    case "reject_adjustment":
      return {
        adjustment: await reject(
          body,
          auth,
          requestId,
          "server_owner_reject_adjustment",
        ),
      };
  }
}

function actionValue(value: unknown): Action {
  if (
    typeof value === "string" && (ACTIONS as readonly string[]).includes(value)
  ) return value as Action;
  throw validationFailed("Financial correction action is unsupported.");
}

async function eligibleSources(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(
      auth,
      "server_owner_financial_correction_source_list",
      base(auth, body),
    )).data,
  ).map((r) => ({
    financial_event_id: str(r, "financial_event_id"),
    event_number: str(r, "event_number"),
    event_type: str(r, "event_type"),
    financial_transaction_id: str(r, "financial_transaction_id"),
    transaction_number: str(r, "transaction_number"),
    amount: decOut(r.amount),
    currency_code: str(r, "currency_code"),
    event_date: str(r, "event_date"),
    label: str(r, "label"),
    can_reverse: bool(r.can_reverse),
    can_adjust: bool(r.can_adjust),
    reversal_recorded: bool(r.reversal_recorded),
    adjustment_recorded: bool(r.adjustment_recorded),
  }));
}

async function list(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  name: string,
  map: (r: Record<string, unknown>) => unknown,
) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows((await rpc(auth, name, base(auth, body))).data).map(map);
}

async function createReversal(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "original_transaction_id",
    "reversal_date",
    "reason",
    "description",
    "duplicate_fingerprint",
  ]);
  return mutation(firstRow(
    (await rpc(auth, "server_owner_create_reversal", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_original_transaction_id: uuidValue(
        body.original_transaction_id,
        "Original transaction ID",
      ),
      p_reversal_date: dateValue(body.reversal_date, "Reversal date"),
      p_reason: trimmedNonblank(body.reason, "Reason"),
      p_description: optional(body.description, "Description"),
      p_duplicate_fingerprint: optional(
        body.duplicate_fingerprint,
        "Duplicate fingerprint",
      ),
      p_request_identifier: requestId,
    })).data,
  ));
}

async function createAdjustment(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
  update: boolean,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_event_id",
    "expected_version_number",
    "financial_account_id",
    "direction",
    "amount",
    "adjustment_date",
    "reporting_currency_code",
    "reason",
    "adjusted_transaction_id",
    "description",
    "duplicate_fingerprint",
  ]);
  const args: Record<string, unknown> = {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_financial_account_id: uuidValue(
      body.financial_account_id,
      "Financial account ID",
    ),
    p_direction: direction(body.direction),
    p_amount: decimal(body.amount, "Adjustment amount"),
    p_adjustment_date: dateValue(body.adjustment_date, "Adjustment date"),
    p_reporting_currency_code: currency(body.reporting_currency_code),
    p_reason: trimmedNonblank(body.reason, "Reason"),
    p_adjusted_transaction_id: body.adjusted_transaction_id == null ||
        body.adjusted_transaction_id === ""
      ? null
      : uuidValue(body.adjusted_transaction_id, "Adjusted transaction ID"),
    p_description: optional(body.description, "Description"),
    p_request_identifier: requestId,
  };
  if (update) {
    args.p_financial_event_id = uuidValue(
      body.financial_event_id,
      "Financial event ID",
    );
    args.p_expected_version_number = version(body.expected_version_number);
  } else {
    args.p_duplicate_fingerprint = optional(
      body.duplicate_fingerprint,
      "Duplicate fingerprint",
    );
  }
  return mutation(
    firstRow(
      (await rpc(
        auth,
        update
          ? "server_owner_update_adjustment"
          : "server_owner_create_adjustment",
        args,
      )).data,
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
  return mutation(
    firstRow(
      (await rpc(auth, name, {
        ...eventArgs(body, auth),
        p_expected_version_number: version(body.expected_version_number),
        p_request_identifier: requestId,
      })).data,
    ),
  );
}

async function reject(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
  name: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_event_id",
    "expected_version_number",
    "rejection_reason",
  ]);
  return mutation(firstRow(
    (await rpc(auth, name, {
      ...eventArgs(body, auth),
      p_expected_version_number: version(body.expected_version_number),
      p_rejection_reason: trimmedNonblank(
        body.rejection_reason,
        "Rejection reason",
      ),
      p_request_identifier: requestId,
    })).data,
  ));
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
const eventArgs = (
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) => ({
  p_verified_owner_auth_subject: auth.actorAuthSubject,
  p_financial_event_id: uuidValue(
    body.financial_event_id,
    "Financial event ID",
  ),
});
const reversalSummary = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  original_transaction_id: str(r, "original_transaction_id"),
  reversal_date: str(r, "reversal_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  version_number: int(r.version_number),
});
const reversalDetail = (r: Record<string, unknown>) => ({
  ...reversalSummary(r),
  reason: str(r, "reason"),
  full_reversal: bool(r.full_reversal),
  reporting_currency_code: str(r, "reporting_currency_code"),
  description: nullable(r.description),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
});
const adjustmentSummary = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  adjusted_transaction_id: nullable(r.adjusted_transaction_id),
  financial_account_id: str(r, "financial_account_id"),
  direction: str(r, "direction"),
  amount: decOut(r.amount),
  currency_code: str(r, "currency_code"),
  adjustment_date: str(r, "adjustment_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  version_number: int(r.version_number),
});
const adjustmentDetail = (r: Record<string, unknown>) => ({
  ...adjustmentSummary(r),
  reason: str(r, "reason"),
  reporting_currency_code: str(r, "reporting_currency_code"),
  description: nullable(r.description),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
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

function rows(data: unknown): Record<string, unknown>[] {
  if (Array.isArray(data) && data.every(isRecord)) return data;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}
function firstRow(data: unknown) {
  const all = rows(data);
  if (all[0]) return all[0];
  throw validationFailed("Financial correction was not found.");
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
function direction(v: unknown) {
  if (v === "INCREASE" || v === "DECREASE") return v;
  throw validationFailed("Adjustment direction is invalid.");
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
    return validationFailed("Financial correction version conflict.");
  }
  if (["23514", "23505", "22P02"].includes(error.code ?? "")) {
    return validationFailed(
      error.message ?? "Financial correction request cannot be completed.",
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
