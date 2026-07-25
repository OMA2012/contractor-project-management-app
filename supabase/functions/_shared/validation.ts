import { validationFailed } from "./errors.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function rejectUnknownFields(
  body: Record<string, unknown>,
  allowed: readonly string[],
): void {
  const allowedSet = new Set(allowed);
  const unknown = Object.keys(body).filter((key) => !allowedSet.has(key));
  if (unknown.length > 0) {
    throw validationFailed("Request contains unsupported fields.");
  }
}

export function normalizedEmail(value: unknown): string {
  if (typeof value !== "string") {
    throw validationFailed("Email is invalid.");
  }
  const email = value.trim().toLowerCase();
  if (!EMAIL_PATTERN.test(email)) {
    throw validationFailed("Email is invalid.");
  }
  return email;
}

export function uuidValue(value: unknown, field = "UUID"): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value.trim())) {
    throw validationFailed(`${field} is invalid.`);
  }
  return value.trim().toLowerCase();
}

export function trimmedNonblank(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw validationFailed(`${field} is required.`);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw validationFailed(`${field} is required.`);
  }
  return trimmed;
}

export const reason = (value: unknown) => trimmedNonblank(value, "Reason");
export const fullName = (value: unknown) => trimmedNonblank(value, "Full name");
