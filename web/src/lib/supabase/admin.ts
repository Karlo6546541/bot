import "server-only";
import { createClient } from "@supabase/supabase-js";
import { env } from "@/lib/env";
import type { Database } from "./database.types";

let cached: ReturnType<typeof createClient<Database>> | null = null;

/**
 * Service-role client: BYPASSES RLS. Only use on the server, after doing an
 * explicit authorization check (access control, admin role, payment service).
 */
export function createAdminClient() {
  if (!env.supabaseServiceRoleKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not set");
  cached ??= createClient<Database>(env.supabaseUrl, env.supabaseServiceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cached;
}

export type AdminClient = ReturnType<typeof createAdminClient>;
