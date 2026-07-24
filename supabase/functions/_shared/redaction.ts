const SENSITIVE_KEY_PATTERN =
  /(authorization|bearer|token|token_hash|digest|service_role|apikey|api_key|password|otp|action_link|invitation_url|reset)/i;

const BEARER_PATTERN = /bearer\s+[a-z0-9._~+/=-]+/gi;
const URL_TOKEN_PATTERN =
  /https?:\/\/[^\s"'<>]+(?:token|otp|code|redirect_to|invitation)[^\s"'<>]*/gi;
const JWT_PATTERN = /\beyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\b/g;
const OTP_PATTERN = /\b\d{6}\b/g;

export function redactString(value: string): string {
  return value
    .replace(URL_TOKEN_PATTERN, "[REDACTED_URL]")
    .replace(BEARER_PATTERN, "Bearer [REDACTED]")
    .replace(JWT_PATTERN, "[REDACTED_JWT]")
    .replace(OTP_PATTERN, "[REDACTED_OTP]");
}

export function redact(value: unknown): unknown {
  if (typeof value === "string") {
    return redactString(value);
  }
  if (Array.isArray(value)) {
    return value.map((item) => redact(item));
  }
  if (value && typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const [key, child] of Object.entries(value)) {
      output[key] = SENSITIVE_KEY_PATTERN.test(key)
        ? "[REDACTED]"
        : redact(child);
    }
    return output;
  }
  return value;
}
