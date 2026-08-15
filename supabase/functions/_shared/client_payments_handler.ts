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
  "verify_client_submitted",
  "submit",
  "approve",
  "reject",
  "request_list",
  "request_detail",
  "request_create",
  "request_update",
  "request_send",
  "request_cancel",
] as const;
type Action = typeof ACTIONS[number];
type RpcError = { code?: string; message?: string };
type RpcResult = { data: unknown; error: RpcError | null };
interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

export function createClientPaymentsHandler(deps: {
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
      return { payments: await list(body, auth) };
    case "detail":
      return { payment: await detail(body, auth) };
    case "create":
      return { payment: await create(body, auth, requestId) };
    case "update":
      return { payment: await update(body, auth, requestId) };
    case "verify_client_submitted":
      return { payment: await verifyClientSubmitted(body, auth, requestId) };
    case "submit":
      return {
        payment: await transition(
          body,
          auth,
          requestId,
          "server_owner_submit_client_payment",
        ),
      };
    case "approve":
      return {
        payment: await transition(
          body,
          auth,
          requestId,
          "server_owner_approve_client_payment",
        ),
      };
    case "reject":
      return { payment: await rejectPayment(body, auth, requestId) };
    case "request_list":
      return { requests: await requestList(body, auth) };
    case "request_detail":
      return { request: await requestDetail(body, auth) };
    case "request_create":
      return { request: await requestCreate(body, auth, requestId) };
    case "request_update":
      return { request: await requestUpdate(body, auth, requestId) };
    case "request_send":
      return {
        request: await requestTransition(
          body,
          auth,
          requestId,
          "server_owner_send_payment_request",
        ),
      };
    case "request_cancel":
      return { request: await requestCancel(body, auth, requestId) };
  }
}

function actionValue(value: unknown): Action {
  if (
    typeof value === "string" && (ACTIONS as readonly string[]).includes(value)
  ) {
    return value as Action;
  }
  throw validationFailed("Client payment action is unsupported.");
}

async function list(body: Record<string, unknown>, auth: AuthenticatedContext) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_client_payment_list", base(auth, body)))
      .data,
  )
    .map(paymentSummary);
}

async function detail(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "financial_event_id"]);
  return paymentDetail(
    firstRow(
      (await rpc(auth, "server_owner_client_payment_detail", {
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
  rejectUnknownFields(body, paymentDraftFields("action"));
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_create_client_payment", {
        ...paymentDraftArgs(body, auth, requestId),
      })).data,
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
    paymentDraftFields(
      "action",
      "financial_event_id",
      "expected_version_number",
    ),
  );
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_update_client_payment", {
        ...paymentDraftArgs(body, auth, requestId),
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
      })).data,
    ),
  );
}

async function verifyClientSubmitted(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_event_id",
    "expected_version_number",
    "received_account_id",
    "notes",
  ]);
  return mutation(
    firstRow(
      (await rpc(auth, "server_owner_verify_client_submitted_payment", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_financial_event_id: uuidValue(
          body.financial_event_id,
          "Financial event ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
        p_received_account_id: uuidValue(
          body.received_account_id,
          "Received account ID",
        ),
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

async function rejectPayment(
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
      (await rpc(auth, "server_owner_reject_client_payment", {
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

async function requestList(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "limit", "offset"]);
  return rows(
    (await rpc(auth, "server_owner_payment_request_list", base(auth, body)))
      .data,
  ).map(requestSummary);
}

async function requestDetail(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "payment_request_id"]);
  return requestDetailRow(
    firstRow(
      (await rpc(auth, "server_owner_payment_request_detail", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_payment_request_id: uuidValue(
          body.payment_request_id,
          "Payment request ID",
        ),
      })).data,
    ),
  );
}

async function requestCreate(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, requestDraftFields("action"));
  return requestMutation(
    firstRow(
      (await rpc(
        auth,
        "server_owner_create_payment_request",
        requestDraftArgs(body, auth, requestId),
      )).data,
    ),
  );
}

async function requestUpdate(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(
    body,
    requestDraftFields(
      "action",
      "payment_request_id",
      "expected_version_number",
    ),
  );
  return requestMutation(
    firstRow(
      (await rpc(auth, "server_owner_update_payment_request", {
        ...requestDraftArgs(body, auth, requestId),
        p_payment_request_id: uuidValue(
          body.payment_request_id,
          "Payment request ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
      })).data,
    ),
  );
}

async function requestTransition(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
  name: string,
) {
  rejectUnknownFields(body, [
    "action",
    "payment_request_id",
    "expected_version_number",
  ]);
  return requestMutation(firstRow(
    (await rpc(auth, name, {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_payment_request_id: uuidValue(
        body.payment_request_id,
        "Payment request ID",
      ),
      p_expected_version_number: version(body.expected_version_number),
      p_request_identifier: requestId,
    })).data,
  ));
}

async function requestCancel(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "payment_request_id",
    "expected_version_number",
    "cancellation_reason",
  ]);
  return requestMutation(
    firstRow(
      (await rpc(auth, "server_owner_cancel_payment_request", {
        p_verified_owner_auth_subject: auth.actorAuthSubject,
        p_payment_request_id: uuidValue(
          body.payment_request_id,
          "Payment request ID",
        ),
        p_expected_version_number: version(body.expected_version_number),
        p_cancellation_reason: trimmedNonblank(
          body.cancellation_reason,
          "Cancellation reason",
        ),
        p_request_identifier: requestId,
      })).data,
    ),
  );
}

function paymentDraftFields(...extra: string[]) {
  return [
    ...extra,
    "project_id",
    "amount",
    "currency_code",
    "received_date",
    "received_account_id",
    "payment_reference",
    "payer_name",
    "notes",
  ];
}
function paymentDraftArgs(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  return {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_project_id: uuidValue(body.project_id, "Project ID"),
    p_amount: decimal(body.amount, "Amount"),
    p_currency_code: currency(body.currency_code),
    p_received_date: dateValue(body.received_date, "Received date"),
    p_received_account_id: optionalUuid(
      body.received_account_id,
      "Received account ID",
    ),
    p_payment_reference: optional(body.payment_reference, "Payment reference"),
    p_payer_name: optional(body.payer_name, "Payer name"),
    p_notes: optional(body.notes, "Notes"),
    p_request_identifier: requestId,
  };
}
function requestDraftFields(...extra: string[]) {
  return [
    ...extra,
    "project_id",
    "requested_amount",
    "currency_code",
    "request_date",
    "due_date",
    "description",
  ];
}
function requestDraftArgs(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  return {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_project_id: uuidValue(body.project_id, "Project ID"),
    p_requested_amount: decimal(body.requested_amount, "Requested amount"),
    p_currency_code: currency(body.currency_code),
    p_request_date: optionalDate(body.request_date, "Request date"),
    p_due_date: optionalDate(body.due_date, "Due date"),
    p_description: optional(body.description, "Description"),
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
  p_offset: bounded(body.offset, 0, 0, 1_000_000),
});
const paymentSummary = (r: Record<string, unknown>) => ({
  ...money(r),
  client_payment_id: str(r, "client_payment_id"),
  financial_event_id: str(r, "financial_event_id"),
  event_number: str(r, "event_number"),
  financial_transaction_id: nullable(r.financial_transaction_id),
  transaction_number: nullable(r.transaction_number),
  project_id: str(r, "project_id"),
  client_id: str(r, "client_id"),
  received_date: str(r, "received_date"),
  event_status: str(r, "event_status"),
  transaction_status: str(r, "transaction_status"),
  is_client_submitted: bool(r.is_client_submitted),
  version_number: int(r.version_number),
});
const paymentDetail = (r: Record<string, unknown>) => ({
  ...paymentSummary(r),
  received_account_id: nullable(r.received_account_id),
  payment_reference: nullable(r.payment_reference),
  payer_name: nullable(r.payer_name),
  submitted_by_client_user_id: nullable(r.submitted_by_client_user_id),
  notes: nullable(r.notes),
  reporting_currency_code: nullable(r.reporting_currency_code),
  submitted_at: nullable(r.submitted_at),
  approved_at: nullable(r.approved_at),
  rejected_at: nullable(r.rejected_at),
  rejection_reason: nullable(r.rejection_reason),
});
const requestSummary = (r: Record<string, unknown>) => ({
  payment_request_id: str(r, "payment_request_id"),
  request_number: str(r, "request_number"),
  project_id: str(r, "project_id"),
  client_id: str(r, "client_id"),
  requested_amount: decOut(r.requested_amount),
  currency_code: str(r, "currency_code"),
  request_date: nullable(r.request_date),
  due_date: nullable(r.due_date),
  status: str(r, "status"),
  effective_status: str(r, "effective_status"),
  sent_at: nullable(r.sent_at),
  viewed_at: nullable(r.viewed_at),
  cancelled_at: nullable(r.cancelled_at),
  version_number: int(r.version_number),
});
const requestDetailRow = (r: Record<string, unknown>) => ({
  ...requestSummary(r),
  description: nullable(r.description),
  cancelled_by: nullable(r.cancelled_by),
  cancellation_reason: nullable(r.cancellation_reason),
  created_at: nullable(r.created_at),
  created_by: nullable(r.created_by),
  updated_at: nullable(r.updated_at),
  updated_by: nullable(r.updated_by),
  paid_amount: decOut(r.paid_amount),
  remaining_amount: decOut(r.remaining_amount),
});
const mutation = (r: Record<string, unknown>) => ({
  financial_event_id: str(r, "financial_event_id"),
  client_payment_id: nullable(r.client_payment_id),
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
const requestMutation = (r: Record<string, unknown>) => ({
  payment_request_id: str(r, "payment_request_id"),
  request_number: str(r, "request_number"),
  status: str(r, "status"),
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
  throw validationFailed("Payment record was not found.");
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
function optionalDate(v: unknown, field: string) {
  return v === undefined || v === null || v === "" ? null : dateValue(v, field);
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
function optionalUuid(v: unknown, field: string) {
  return v === undefined || v === null || v === "" ? null : uuidValue(v, field);
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
    return validationFailed("Payment version conflict.");
  }
  if (["23514", "23505", "22P02"].includes(error.code ?? "")) {
    return validationFailed(
      error.message ?? "Payment request cannot be completed.",
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
