import { createInvitationHandler } from "../_shared/client_invitation_handler.ts";

Deno.serve(createInvitationHandler("accept-client-invitation"));
