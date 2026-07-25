import { createLifecycleHandler } from "../_shared/client_lifecycle_handler.ts";

Deno.serve(createLifecycleHandler("disable-client-account"));
