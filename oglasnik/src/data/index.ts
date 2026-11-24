import { LokalniBackend } from './lokalno';
import { SupabaseBackend } from './supabase';
import type { Backend } from './types';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const kljuc = import.meta.env.VITE_SUPABASE_KEY as string | undefined;

/** Supabase kad je build dobio postavke, inače lokalni (demo) način. */
export const backend: Backend = url && kljuc ? new SupabaseBackend(url, kljuc) : new LokalniBackend();
