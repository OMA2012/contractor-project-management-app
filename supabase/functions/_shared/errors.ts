export type ErrorCode =
  | "bad_request"
  | "unauthorized"
  | "forbidden"
  | "validation_failed"
  | "internal_error";

export class SafeError extends Error {
  readonly status: number;
  readonly code: ErrorCode;

  constructor(status: number, code: ErrorCode, message: string) {
    super(message);
    this.name = "SafeError";
    this.status = status;
    this.code = code;
  }
}

export function badRequest(message = "Invalid request."): SafeError {
  return new SafeError(400, "bad_request", message);
}

export function unauthorized(
  message = "Authentication is required.",
): SafeError {
  return new SafeError(401, "unauthorized", message);
}

export function forbidden(message = "Request is not allowed."): SafeError {
  return new SafeError(403, "forbidden", message);
}

export function validationFailed(message = "Validation failed."): SafeError {
  return new SafeError(422, "validation_failed", message);
}
