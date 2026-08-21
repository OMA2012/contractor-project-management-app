const MAX_DOCUMENT_BYTES = 26_214_400;
const CLAMD_SOCKET = "/run/clamav/clamd.ctl";
const CLAMD_RESPONSE_MAX_BYTES = 4096;
const CLAMD_TIMEOUT_MS = 8000;

export type ScanResult =
  | { result: "CLEAN" }
  | { result: "MALICIOUS"; malware_name: string }
  | { result: "ERROR" };

export interface MalwareScanner {
  scan(bytes: Uint8Array): Promise<ScanResult>;
  ready(): Promise<boolean>;
}

export interface HandlerOptions {
  token: string;
  scanner: MalwareScanner;
  maxDocumentBytes?: number;
}

class PayloadTooLargeError extends Error {}

export function createHandler(options: HandlerOptions) {
  if (!options.token) throw new Error("SCANNER_TOKEN is required");
  const maxDocumentBytes = options.maxDocumentBytes ?? MAX_DOCUMENT_BYTES;

  return async (request: Request): Promise<Response> => {
    const path = new URL(request.url).pathname;

    if (path === "/health") {
      if (request.method !== "GET") return errorResponse(405);
      const ready = await options.scanner.ready().catch(() => false);
      return jsonResponse(
        { status: ready ? "ready" : "not_ready" },
        ready ? 200 : 503,
      );
    }

    if (path !== "/scan") return errorResponse(404);
    if (request.method !== "POST") return errorResponse(405);
    if (!authorized(request.headers.get("authorization"), options.token)) {
      return errorResponse(401);
    }

    const mediaType = request.headers.get("content-type")?.split(";", 1)[0]
      .trim().toLowerCase();
    if (mediaType !== "application/octet-stream") return errorResponse(415);

    const declaredLength = request.headers.get("content-length");
    if (declaredLength !== null) {
      const parsedLength = Number(declaredLength);
      if (!Number.isSafeInteger(parsedLength) || parsedLength < 0) {
        return errorResponse(400);
      }
      if (parsedLength > maxDocumentBytes) return errorResponse(413);
    }

    try {
      const bytes = await readBoundedBody(request, maxDocumentBytes);
      const result = await options.scanner.scan(bytes);
      return jsonResponse(result, 200);
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return errorResponse(413);
      // Scanner failures use the client's explicit fail-closed result contract.
      return jsonResponse({ result: "ERROR" }, 200);
    }
  };
}

export class ClamdScanner implements MalwareScanner {
  constructor(
    private readonly socketPath = CLAMD_SOCKET,
    private readonly timeoutMs = CLAMD_TIMEOUT_MS,
  ) {}

  async ready(): Promise<boolean> {
    try {
      const response = await this.exchange(async (connection) => {
        await writeAll(connection, new TextEncoder().encode("zPING\0"));
        return await readClamdResponse(connection);
      });
      return response === "PONG";
    } catch {
      return false;
    }
  }

  async scan(bytes: Uint8Array): Promise<ScanResult> {
    try {
      const response = await this.exchange(async (connection) => {
        await writeAll(connection, new TextEncoder().encode("zINSTREAM\0"));
        for (let offset = 0; offset < bytes.byteLength; offset += 64 * 1024) {
          const chunk = bytes.subarray(
            offset,
            Math.min(offset + 64 * 1024, bytes.byteLength),
          );
          const length = new Uint8Array(4);
          new DataView(length.buffer).setUint32(0, chunk.byteLength, false);
          await writeAll(connection, length);
          await writeAll(connection, chunk);
        }
        await writeAll(connection, new Uint8Array(4));
        return await readClamdResponse(connection);
      });
      return parseClamdScanResponse(response);
    } catch {
      return { result: "ERROR" };
    }
  }

  private async exchange<T>(
    operation: (connection: Deno.Conn) => Promise<T>,
  ): Promise<T> {
    let connection: Deno.Conn | undefined;
    let expired = false;
    let timeoutId: ReturnType<typeof setTimeout> | undefined;

    const work = (async () => {
      connection = await Deno.connect({
        transport: "unix",
        path: this.socketPath,
      });
      if (expired) {
        connection.close();
        throw new Error("clamd operation timed out");
      }
      return await operation(connection);
    })();
    const timeout = new Promise<never>((_, reject) => {
      timeoutId = setTimeout(() => {
        expired = true;
        try {
          connection?.close();
        } catch {
          // The operation may already have closed the socket.
        }
        reject(new Error("clamd operation timed out"));
      }, this.timeoutMs);
    });

    try {
      return await Promise.race([work, timeout]);
    } finally {
      expired = true;
      if (timeoutId !== undefined) clearTimeout(timeoutId);
      try {
        connection?.close();
      } catch {
        // Closing an already-closed connection is harmless.
      }
    }
  }
}

function parseClamdScanResponse(response: string): ScanResult {
  if (response === "stream: OK") return { result: "CLEAN" };
  const malicious = /^stream: (.+) FOUND$/.exec(response);
  if (malicious?.[1]) {
    return { result: "MALICIOUS", malware_name: malicious[1] };
  }
  return { result: "ERROR" };
}

async function readClamdResponse(connection: Deno.Conn): Promise<string> {
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total <= CLAMD_RESPONSE_MAX_BYTES) {
    const buffer = new Uint8Array(
      Math.min(512, CLAMD_RESPONSE_MAX_BYTES + 1 - total),
    );
    const count = await connection.read(buffer);
    if (count === null) break;
    const chunk = buffer.subarray(0, count);
    const terminator = chunk.indexOf(0);
    if (terminator >= 0) {
      chunks.push(chunk.subarray(0, terminator));
      total += terminator;
      return new TextDecoder().decode(joinBytes(chunks, total)).trim();
    }
    chunks.push(chunk);
    total += count;
  }
  if (total > CLAMD_RESPONSE_MAX_BYTES) {
    throw new Error("clamd response too large");
  }
  return new TextDecoder().decode(joinBytes(chunks, total)).trim();
}

async function writeAll(connection: Deno.Conn, bytes: Uint8Array) {
  let offset = 0;
  while (offset < bytes.byteLength) {
    offset += await connection.write(bytes.subarray(offset));
  }
}

async function readBoundedBody(
  request: Request,
  maxBytes: number,
): Promise<Uint8Array> {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (total + value.byteLength > maxBytes) {
      await reader.cancel();
      throw new PayloadTooLargeError();
    }
    chunks.push(value);
    total += value.byteLength;
  }
  return joinBytes(chunks, total);
}

function joinBytes(chunks: Uint8Array[], total: number): Uint8Array {
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return joined;
}

function authorized(header: string | null, expectedToken: string): boolean {
  const match = /^Bearer ([^\s]+)$/.exec(header ?? "");
  if (!match) return false;
  return constantTimeEqual(match[1], expectedToken);
}

function constantTimeEqual(actual: string, expected: string): boolean {
  const encoder = new TextEncoder();
  const actualBytes = encoder.encode(actual);
  const expectedBytes = encoder.encode(expected);
  const length = Math.max(actualBytes.byteLength, expectedBytes.byteLength);
  let difference = actualBytes.byteLength ^ expectedBytes.byteLength;
  for (let index = 0; index < length; index++) {
    difference |= (actualBytes[index] ?? 0) ^ (expectedBytes[index] ?? 0);
  }
  return difference === 0;
}

function errorResponse(status: number): Response {
  return jsonResponse({ result: "ERROR" }, status);
}

function jsonResponse(body: unknown, status: number): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

async function run(): Promise<void> {
  const scanner = new ClamdScanner();
  if (Deno.args.includes("--wait-for-clamd")) {
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline) {
      if (await scanner.ready()) return;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    throw new Error("clamd did not become ready");
  }

  const token = Deno.env.get("SCANNER_TOKEN") ?? "";
  if (!token) throw new Error("SCANNER_TOKEN is required");
  const portText = Deno.env.get("PORT") ?? "8080";
  const port = Number(portText);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new Error("PORT is invalid");
  }

  Deno.serve(
    { hostname: "0.0.0.0", port },
    createHandler({ token, scanner }),
  );
}

if (import.meta.main) {
  try {
    await run();
  } catch {
    console.error("document scanner failed to start");
    Deno.exit(1);
  }
}
