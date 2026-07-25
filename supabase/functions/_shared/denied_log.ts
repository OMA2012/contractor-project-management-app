import { validationFailed } from "./errors.ts";
import { redact } from "./redaction.ts";

const ACTIONS = new Set([
  "client_invitation_create",
  "client_invitation_resend",
  "client_invitation_revoke",
  "client_invitation_accept",
  "client_account_suspend",
  "client_account_reactivate",
  "client_account_disable",
]);
const ENTITY_TYPES = new Set(["user", "user_invitation"]);
const REASONS = new Set([
  "authorization_denied",
  "inactive_actor",
  "insufficient_role",
  "invalid_actor_type",
  "invalid_target_state",
]);

export interface DeniedLogArgs {
  action: string;
  entityType: string;
  reasonCode: string;
  metadata?: Record<string, unknown>;
}

export function deniedLogArgs(input: DeniedLogArgs): DeniedLogArgs {
  if (!ACTIONS.has(input.action)) {
    throw validationFailed("Denied-log action is invalid.");
  }
  if (!ENTITY_TYPES.has(input.entityType)) {
    throw validationFailed("Denied-log entity type is invalid.");
  }
  if (!REASONS.has(input.reasonCode)) {
    throw validationFailed("Denied-log reason code is invalid.");
  }
  return {
    action: input.action,
    entityType: input.entityType,
    reasonCode: input.reasonCode,
    metadata: redact(input.metadata ?? {}) as Record<string, unknown>,
  };
}
