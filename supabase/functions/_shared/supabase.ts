import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { AppEnv } from "./env.ts";

export function createServiceClient(env: AppEnv): SupabaseClient {
  return createClient(env.supabaseUrl, env.serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}
