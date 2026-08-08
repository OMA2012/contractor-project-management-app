import { createDocumentStorageHandler } from "../_shared/document_storage_handler.ts";

Deno.serve(createDocumentStorageHandler("document-upload-authorize"));
