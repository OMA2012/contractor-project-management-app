import { validationFailed } from "./errors.ts";

const TOKEN_BYTES = 32;
const URL_SAFE_PATTERN = /^[A-Za-z0-9_-]+$/;

export function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

export function decodeBase64Url(token: string): Uint8Array {
  if (!URL_SAFE_PATTERN.test(token) || token.includes("=")) {
    throw validationFailed("Invitation token is invalid.");
  }
  const padded = token.replaceAll("-", "+").replaceAll("_", "/").padEnd(
    Math.ceil(token.length / 4) * 4,
    "=",
  );
  let binary: string;
  try {
    binary = atob(padded);
  } catch {
    throw validationFailed("Invitation token is invalid.");
  }
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  if (bytes.length !== TOKEN_BYTES) {
    throw validationFailed("Invitation token is invalid.");
  }
  return bytes;
}

export function generateInvitationToken(): string {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

export async function sha256Digest(bytes: Uint8Array): Promise<Uint8Array> {
  const input = new Uint8Array(bytes);
  return new Uint8Array(await crypto.subtle.digest("SHA-256", input));
}

export function byteaHex(bytes: Uint8Array): string {
  return `\\x${
    Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("")
  }`;
}
