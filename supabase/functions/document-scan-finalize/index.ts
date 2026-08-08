import { createDocumentScanHandler } from "../_shared/document_scan_handler.ts";

Deno.serve(createDocumentScanHandler());
