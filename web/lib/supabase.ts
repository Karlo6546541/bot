// Klijenti baze. Javne stranice koriste klijent bez kolačića (može se
// keširati, ISR); prijavljeni korisnik ide kroz preglednik ili poslužitelj s kolačićima.
import { createBrowserClient, createServerClient } from '@supabase/ssr';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { SUPABASE_KEY, SUPABASE_URL, imaBazu } from './config';

/** Javni upiti (bez prijave) s kratkim keširanjem; `null` kad baza nije spojena. */
export function javniKlijent(revalidate = 60): SupabaseClient | null {
  if (!imaBazu()) return null;
  return createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) => fetch(input, { ...init, next: { revalidate } } as RequestInit),
    },
  });
}

let preglednik: SupabaseClient | null = null;
/** Klijent u pregledniku (prijava, objava, poruke). */
export function klijentPreglednika(): SupabaseClient {
  preglednik ??= createBrowserClient(SUPABASE_URL, SUPABASE_KEY);
  return preglednik;
}

/** Klijent na poslužitelju koji čita prijavu iz kolačića (privatne stranice). */
export async function klijentServera(): Promise<SupabaseClient> {
  const { cookies } = await import('next/headers');
  const store = await cookies();
  return createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          list.forEach(({ name, value, options }) => store.set(name, value, options));
        } catch {
          /* pozvano iz Server Componenta: osvježavanje kolačića radi proxy */
        }
      },
    },
  });
}
