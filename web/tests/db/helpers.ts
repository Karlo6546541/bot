import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { existsSync } from "node:fs";
import path from "node:path";
import type { Database } from "@/lib/supabase/database.types";

const envFile = path.resolve(__dirname, "../../.env.local");
if (existsSync(envFile)) process.loadEnvFile(envFile);

export const URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY!;
export type DB = SupabaseClient<Database>;

const opts = { auth: { persistSession: false, autoRefreshToken: false } };
export const anon = (): DB => createClient<Database>(URL, ANON, opts);
export const service = (): DB => createClient<Database>(URL, SERVICE, opts);

export async function signedIn(email: string, password = "lozinka123"): Promise<DB> {
  const c = anon();
  const { error } = await c.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`login ${email}: ${error.message}`);
  return c;
}

export async function createTempUser(prefix: string): Promise<{ id: string; email: string; client: DB }> {
  const email = `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}@kadar.test`;
  const { data, error } = await service().auth.admin.createUser({ email, password: "lozinka123", email_confirm: true });
  if (error || !data.user) throw new Error(error?.message);
  return { id: data.user.id, email, client: await signedIn(email) };
}

export async function chapterBySeries(slug: string, number: number) {
  const { data } = await service()
    .from("chapters")
    .select("*, series!inner(*)")
    .eq("series.slug", slug)
    .eq("number", number)
    .single();
  if (!data) throw new Error(`chapter ${slug}#${number} not found — run npm run seed`);
  return data;
}
