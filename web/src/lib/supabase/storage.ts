import { env } from "@/lib/env";

export function coverUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  return `${env.supabaseUrl || process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/covers/${path}`;
}
