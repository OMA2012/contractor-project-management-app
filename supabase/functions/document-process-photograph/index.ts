import { createDocumentImageHandler } from "../_shared/document_image_handler.ts";

Deno.serve(createDocumentImageHandler());
