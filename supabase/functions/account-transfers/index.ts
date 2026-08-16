import { createAccountTransferHandler } from "../_shared/account_transfer_handler.ts";

Deno.serve(createAccountTransferHandler());
