import { withSupabase } from "@supabase/server";
import type { SupabaseContext } from "@supabase/server";
import type { AppEnv } from "./env.ts";
import { unauthorized } from "./errors.ts";
import { createServiceClient } from "./supabase.ts";

export interface AuthenticatedContext {
  actorAuthSubject: string;
  context: SupabaseContext;
  serviceClient: ReturnType<typeof createServiceClient>;
}

export async function authenticateRequest(
  req: Request,
  env: AppEnv,
): Promise<AuthenticatedContext> {
  let verifiedContext: SupabaseContext | null = null;
  const response = await withSupabase(
    {
      auth: "user",
      cors: "disabled",
      env: {
        url: env.supabaseUrl,
        publishableKeys: { default: env.publishableKey },
        secretKeys: { default: env.serviceRoleKey },
        jwks: env.jwks ?? new URL(env.jwksUrl),
      },
    },
    (_request, context) => {
      verifiedContext = context;
      return Promise.resolve(new Response(null, { status: 204 }));
    },
  )(req);

  const context = verifiedContext as SupabaseContext | null;
  if (response.status !== 204 || !context?.userClaims?.id) {
    throw unauthorized();
  }
  return {
    actorAuthSubject: context.userClaims.id,
    context,
    serviceClient: createServiceClient(env),
  };
}
