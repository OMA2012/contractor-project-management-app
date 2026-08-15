import { createClientPaymentsHandler } from "../_shared/client_payments_handler.ts";

Deno.serve(createClientPaymentsHandler());
