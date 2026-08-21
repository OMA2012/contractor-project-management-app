import { ClamdScanner } from "./main.ts";

const socket = Deno.env.get("CLAMD_SOCKET");

Deno.test({
  name: "clamd detects the standard harmless EICAR test signature",
  ignore: !socket,
  async fn() {
    // Constructed at runtime so no standalone test sample is committed.
    const segments = [
      "X5O!P%@AP[4\\PZX54(P^)",
      "7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!",
      "$H+H*",
    ];
    const result = await new ClamdScanner(socket).scan(
      new TextEncoder().encode(segments.join("")),
    );
    if (result.result !== "MALICIOUS") {
      throw new Error(`expected MALICIOUS, got ${result.result}`);
    }
  },
});
