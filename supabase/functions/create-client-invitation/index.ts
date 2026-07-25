import { createInvitationHandler } from "../_shared/client_invitation_handler.ts";

Deno.serve(createInvitationHandler("create-client-invitation"));
