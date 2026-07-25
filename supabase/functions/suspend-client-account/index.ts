import { createLifecycleHandler } from "../_shared/client_lifecycle_handler.ts";

Deno.serve(createLifecycleHandler("suspend-client-account"));
