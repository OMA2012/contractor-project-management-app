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

const AUTHZ_ERROR_CODES = new Set(["42501", "PGRST301"]);
const ACTIONS = [
  "list",
  "detail",
  "balance",
  "balances_by_currency",
  "cash_totals_by_currency",
  "bank_totals_by_currency",
  "create",
  "update",
  "activate",
  "deactivate",
  "archive",
] as const;

type Action = typeof ACTIONS[number];
type RpcError = { code?: string; message?: string };
type RpcResult = { data: unknown; error: RpcError | null };
interface ServiceClient {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
}

export interface FinancialAccountDependencies {
  loadEnv?: () => AppEnv;
  authenticate?: (req: Request, env: AppEnv) => Promise<AuthenticatedContext>;
}

export function createFinancialAccountHandler(
  deps: FinancialAccountDependencies = {},
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
      const data = await dispatch(body, auth, requestId);
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
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
): Promise<Record<string, unknown>> {
  const action = actionValue(body.action);
  switch (action) {
    case "list":
      return { accounts: await listAccounts(body, auth) };
    case "detail":
      return { account: await detail(body, auth) };
    case "balance":
      return { balance: await balance(body, auth) };
    case "balances_by_currency":
      return {
        balances: await currencyRows(
          body,
          auth,
          "server_owner_financial_account_balances_by_currency",
        ),
      };
    case "cash_totals_by_currency":
      return {
        totals: await currencyRows(
          body,
          auth,
          "server_owner_cash_totals_by_currency",
        ),
      };
    case "bank_totals_by_currency":
      return {
        totals: await currencyRows(
          body,
          auth,
          "server_owner_bank_totals_by_currency",
        ),
      };
    case "create":
      return { account: await createAccount(body, auth, requestId) };
    case "update":
      return { account: await updateAccount(body, auth, requestId) };
    case "activate":
      return {
        account: await lifecycle(
          body,
          auth,
          requestId,
          "server_owner_activate_financial_account",
        ),
      };
    case "deactivate":
      return {
        account: await lifecycle(
          body,
          auth,
          requestId,
          "server_owner_deactivate_financial_account",
        ),
      };
    case "archive":
      return {
        account: await lifecycle(
          body,
          auth,
          requestId,
          "server_owner_archive_financial_account",
        ),
      };
  }
}

async function updateAccount(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_account_id",
    "expected_version_number",
    "name",
    "account_type",
    "currency_code",
    "bank_name",
    "masked_account_identifier",
    "notes",
  ]);
  const result = await rpc(
    auth,
    "server_owner_update_financial_account_metadata",
    {
      p_verified_owner_auth_subject: auth.actorAuthSubject,
      p_financial_account_id: uuidValue(
        body.financial_account_id,
        "Financial account ID",
      ),
      p_expected_version_number: version(body.expected_version_number),
      p_name: trimmedNonblank(body.name, "Name"),
      p_account_type: accountTypeInput(body.account_type),
      p_currency_code: currencyInput(body.currency_code),
      p_bank_name: optionalTrimmed(body.bank_name, "Bank name"),
      p_masked_account_identifier: optionalTrimmed(
        body.masked_account_identifier,
        "Masked account identifier",
      ),
      p_notes: optionalTrimmed(body.notes, "Notes"),
      p_request_identifier: requestId,
    },
  );
  return mutationRow(firstRow(result.data));
}

function actionValue(value: unknown): Action {
  if (
    typeof value !== "string" || !(ACTIONS as readonly string[]).includes(value)
  ) {
    throw validationFailed("Financial account action is unsupported.");
  }
  return value as Action;
}

async function listAccounts(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "include_archived", "limit", "offset"]);
  const result = await rpc(auth, "server_owner_financial_account_list", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_include_archived: optionalBoolean(body.include_archived, false),
    p_limit: boundedInteger(body.limit, "Limit", 50, 1, 100),
    p_offset: boundedInteger(body.offset, "Offset", 0, 0, 1_000_000),
  });
  return rows(result.data).map(accountSummary);
}

async function detail(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "financial_account_id"]);
  const result = await rpc(auth, "server_owner_financial_account_detail", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_financial_account_id: uuidValue(
      body.financial_account_id,
      "Financial account ID",
    ),
  });
  return accountDetail(firstRow(result.data));
}

async function balance(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
) {
  rejectUnknownFields(body, ["action", "financial_account_id"]);
  const result = await rpc(auth, "server_owner_financial_account_balance", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_financial_account_id: uuidValue(
      body.financial_account_id,
      "Financial account ID",
    ),
  });
  const row = firstRow(result.data);
  return {
    financial_account_id: stringField(row, "financial_account_id"),
    account_number: stringField(row, "account_number"),
    account_type: accountTypeField(row.account_type),
    currency_code: currencyField(row.currency_code),
    balance: decimalString(row.balance, "Balance"),
  };
}

async function currencyRows(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  name: string,
) {
  rejectUnknownFields(body, ["action"]);
  const result = await rpc(auth, name, {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
  });
  return rows(result.data).map((row) => ({
    currency_code: currencyField(row.currency_code),
    balance: decimalString(row.balance, "Balance"),
  }));
}

async function createAccount(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
) {
  rejectUnknownFields(body, [
    "action",
    "name",
    "account_type",
    "currency_code",
    "bank_name",
    "masked_account_identifier",
    "notes",
    "is_active",
  ]);
  const result = await rpc(auth, "server_owner_create_financial_account", {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_name: trimmedNonblank(body.name, "Name"),
    p_account_type: accountTypeInput(body.account_type),
    p_currency_code: currencyInput(body.currency_code),
    p_bank_name: optionalTrimmed(body.bank_name, "Bank name"),
    p_masked_account_identifier: optionalTrimmed(
      body.masked_account_identifier,
      "Masked account identifier",
    ),
    p_encrypted_account_details: null,
    p_is_active: optionalBoolean(body.is_active, true),
    p_notes: optionalTrimmed(body.notes, "Notes"),
    p_request_identifier: requestId,
  });
  return mutationRow(firstRow(result.data));
}

async function lifecycle(
  body: Record<string, unknown>,
  auth: AuthenticatedContext,
  requestId: string,
  name: string,
) {
  rejectUnknownFields(body, [
    "action",
    "financial_account_id",
    "expected_version_number",
  ]);
  const result = await rpc(auth, name, {
    p_verified_owner_auth_subject: auth.actorAuthSubject,
    p_financial_account_id: uuidValue(
      body.financial_account_id,
      "Financial account ID",
    ),
    p_expected_version_number: version(body.expected_version_number),
    p_request_identifier: requestId,
  });
  return lifecycleRow(firstRow(result.data));
}

async function rpc(
  auth: AuthenticatedContext,
  name: string,
  args: Record<string, unknown>,
) {
  const result = await serviceClient(auth).rpc(name, args);
  if (!result.error) return result;
  throw mapDatabaseError(result.error);
}

function accountSummary(row: Record<string, unknown>) {
  return {
    id: stringField(row, "id"),
    account_number: stringField(row, "account_number"),
    name: stringField(row, "name"),
    account_type: accountTypeField(row.account_type),
    currency_code: currencyField(row.currency_code),
    bank_name: nullableString(row.bank_name),
    masked_account_identifier: nullableString(row.masked_account_identifier),
    is_active: booleanField(row.is_active, "is_active"),
    archived_at: nullableString(row.archived_at),
    version_number: integerField(row.version_number, "version_number"),
  };
}

function accountDetail(row: Record<string, unknown>) {
  return {
    ...accountSummary(row),
    notes: nullableString(row.notes),
    archived_by: nullableString(row.archived_by),
    created_at: stringField(row, "created_at"),
    created_by: stringField(row, "created_by"),
    updated_at: stringField(row, "updated_at"),
    updated_by: stringField(row, "updated_by"),
  };
}

function mutationRow(row: Record<string, unknown>) {
  return {
    financial_account_id: stringField(row, "financial_account_id"),
    account_number: stringField(row, "account_number"),
    version_number: integerField(row.version_number, "version_number"),
  };
}

function lifecycleRow(row: Record<string, unknown>) {
  const out: Record<string, unknown> = {
    financial_account_id: stringField(row, "financial_account_id"),
    is_active: booleanField(row.is_active, "is_active"),
    version_number: integerField(row.version_number, "version_number"),
  };
  if (row.archived_at !== undefined) {
    out.archived_at = nullableString(row.archived_at);
  }
  if (row.archived_by !== undefined) {
    out.archived_by = nullableString(row.archived_by);
  }
  return out;
}

function rows(data: unknown): Record<string, unknown>[] {
  if (Array.isArray(data) && data.every(isRecord)) return data;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function firstRow(data: unknown): Record<string, unknown> {
  const all = rows(data);
  if (all.length > 0) return all[0];
  throw validationFailed("Financial account was not found.");
}

function stringField(row: Record<string, unknown>, name: string): string {
  if (typeof row[name] === "string" && row[name] !== "") return row[name];
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function booleanField(value: unknown, field: string): boolean {
  if (typeof value === "boolean") return value;
  throw new SafeError(
    500,
    "internal_error",
    `Database response ${field} was invalid.`,
  );
}

function integerField(value: unknown, field: string): number {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  throw new SafeError(
    500,
    "internal_error",
    `Database response ${field} was invalid.`,
  );
}

function decimalString(value: unknown, field: string): string {
  if (typeof value === "string" && /^-?\d+(\.\d+)?$/.test(value)) return value;
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    return String(value);
  }
  throw new SafeError(500, "internal_error", `${field} was invalid.`);
}

function accountTypeField(value: unknown): "CASH" | "BANK" {
  if (value === "CASH" || value === "BANK") return value;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function accountTypeInput(value: unknown): "CASH" | "BANK" {
  if (value === "CASH" || value === "BANK") return value;
  throw validationFailed("Account type is invalid.");
}

function currencyField(value: unknown): string {
  if (typeof value === "string" && /^[A-Z]{3}$/.test(value)) return value;
  throw new SafeError(500, "internal_error", "Database response was invalid.");
}

function currencyInput(value: unknown): string {
  if (typeof value === "string" && /^[A-Z]{3}$/.test(value)) return value;
  throw validationFailed("Currency code is invalid.");
}

function optionalTrimmed(value: unknown, field: string): string | null {
  return value === undefined || value === null
    ? null
    : trimmedNonblank(value, field);
}

function optionalBoolean(value: unknown, fallback: boolean): boolean {
  if (value === undefined || value === null) return fallback;
  if (typeof value === "boolean") return value;
  throw validationFailed("Boolean input is invalid.");
}

function boundedInteger(
  value: unknown,
  field: string,
  fallback: number,
  min: number,
  max: number,
): number {
  const actual = value === undefined || value === null ? fallback : value;
  if (
    typeof actual !== "number" || !Number.isInteger(actual) || actual < min ||
    actual > max
  ) {
    throw validationFailed(`${field} is invalid.`);
  }
  return actual;
}

function version(value: unknown): number {
  return boundedInteger(value, "Expected version number", 0, 1, 2_147_483_647);
}

function serviceClient(auth: AuthenticatedContext): ServiceClient {
  return auth.serviceClient as unknown as ServiceClient;
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
  if (error.code === "40001") {
    return validationFailed("Financial account version conflict.");
  }
  if (
    error.code === "23514" || error.code === "23505" || error.code === "22P02"
  ) {
    return validationFailed("Financial account request cannot be completed.");
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
