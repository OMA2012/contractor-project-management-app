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
  "rate_lookup",
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

export function createCurrencyExchangeHandler(deps: {
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
      return { currency_exchanges: await list(body, auth) };
    case "detail":
      return { currency_exchange: await detail(body, auth) };
    case "rate_lookup":
      return { exchange_rates: await rateLookup(body, auth) };
    case "create":
      return { currency_exchange: await create(body, auth, requestId) };
    case "update":
      return { currency_exchange: await update(body, auth, requestId) };
    case "submit":
      return {
        currency_exchange: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_currency_exchange",
        ),
      };
    case "approve":
      return {
        currency_exchange: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_currency_exchange",
        ),
      };
    case "reject":
      return { currency_exchange: await rejectExchange(body, auth, requestId) };
  }
}

async function rateLookup(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, [
    "action",
    "source_currency_code",
    "destination_currency_code",
    "exchange_date",
    "limit",
    "offset",
  ]);
  return rows(
    (await rpc(auth, "server_owner_exchange_rate_picker_list", {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_source_currency_code: currency(body.source_currency_code),
      p_destination_currency_code: currency(body.destination_currency_code),
      p_rate_date: dateValue(body.exchange_date, "Exchange date"),
      p_limit: bounded(body.limit, 50, 1, 100),
      p_offset: bounded(body.offset, 0, 0, 1000000),
    })).data,
  ).map(rateLookupRow);
}

function actionValue(value: unknown): Action {
  if (
    typeof value === "string" && (ACTIONS as readonly string[]).includes(value)
  ) return value as Action;
  throw validationFailed("Currency exchange action is unsupported.");
}

async function list(body: Record<string, unknown>, auth: AuthenticatedContext) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_currency_exchange_list", {
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
      (await rpc(auth, "server_owner_currency_exchange_detail", {
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
        "server_owner_create_currency_exchange",
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
      (await rpc(auth, "server_owner_update_currency_exchange", {
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

async function rejectExchange(
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
      (await rpc(auth, "server_owner_reject_currency_exchange", {
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
    "source_amount",
    "exchange_rate_id",
    "fee_amount",
    "fee_account_id",
    "exchange_date",
    "project_id",
    "reference",
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
    p_source_amount: decimal(body.source_amount, "Source amount"),
    p_exchange_rate_id: uuidValue(body.exchange_rate_id, "Exchange rate ID"),
    p_fee_amount: optionalDecimal(body.fee_amount, "Fee amount") ?? "0",
    p_fee_account_id: optionalUuid(body.fee_account_id, "Fee account ID"),
    p_exchange_date: dateValue(body.exchange_date, "Exchange date"),
    p_project_id: optionalUuid(body.project_id, "Project ID"),
    p_reference: optional(body.reference, "Reference"),
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
  currency_exchange_id: str(r, "currency_exchange_id"),
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: str(r, "financial_transaction_id"),
  transaction_number: str(r, "transaction_number"),
  project_id: nullable(r.project_id),
  client_id: nullable(r.client_id),
  source_account_id: str(r, "source_account_id"),
  destination_account_id: str(r, "destination_account_id"),
  source_amount: decOut(r.source_amount),
  source_currency_code: str(r, "source_currency_code"),
  destination_amount: decOut(r.destination_amount),
  destination_currency_code: str(r, "destination_currency_code"),
  fee_amount: decOut(r.fee_amount),
  fee_currency_code: nullable(r.fee_currency_code),
  exchange_date: str(r, "exchange_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  version_number: int(r.version_number),
});
const detailRow = (r: Record<string, unknown>) => ({
  ...summary(r),
  exchange_rate_id: str(r, "exchange_rate_id"),
  rate_base_currency_code: str(r, "rate_base_currency_code"),
  rate_quote_currency_code: str(r, "rate_quote_currency_code"),
  rate_value: decOut(r.rate_value),
  rate_source: str(r, "rate_source"),
  fee_account_id: nullable(r.fee_account_id),
  rounding_result: decOut(r.rounding_result),
  reference: nullable(r.reference),
  reporting_currency_code: nullable(r.reporting_currency_code),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
});
const rateLookupRow = (r: Record<string, unknown>) => ({
  exchange_rate_id: str(r, "id"),
  rate_date: str(r, "rate_date"),
  base_currency_code: str(r, "base_currency_code"),
  quote_currency_code: str(r, "quote_currency_code"),
  rate_value: decOut(r.rate_value),
  source: str(r, "source"),
});
const mutation = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  financial_transaction_id: nullable(r.financial_transaction_id),
  currency_exchange_id: nullable(r.currency_exchange_id),
  event_number: nullable(r.event_number),
  transaction_number: nullable(r.transaction_number),
  destination_amount: r.destination_amount == null
    ? null
    : decOut(r.destination_amount),
  rounding_result: r.rounding_result == null ? null : decOut(r.rounding_result),
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
  throw validationFailed("Currency exchange was not found.");
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
function optionalDecimal(v: unknown, field: string) {
  if (v === undefined || v === null || v === "") return null;
  return decimal(v, field);
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
function optionalUuid(v: unknown, field: string) {
  return v === undefined || v === null || v === "" ? null : uuidValue(v, field);
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
    return validationFailed("Currency exchange version conflict.");
  }
  if (["23514", "23505", "22P02"].includes(error.code ?? "")) {
    return validationFailed(
      error.message ?? "Currency exchange request cannot be completed.",
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
