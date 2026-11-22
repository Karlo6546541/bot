import type { SupabaseClient, User } from '@supabase/supabase-js';
import type { Profil } from './types';

/** Samo putanje unutar stranice (sprječava preusmjeravanje na tuđe adrese). */
export function sigurnoNatrag(v: string | null | undefined): string {
  return v && v.startsWith('/') && !v.startsWith('//') && !v.includes('\\') ? v : '/';
}

/** Profil se stvara pri prvoj prijavi (i za Google račune). */
export async function osigurajProfil(sb: SupabaseClient, user: User): Promise<Profil | null> {
  const postoji = await sb.from('oglasnik_profili').select('*').eq('id', user.id).maybeSingle();
  if (postoji.data) return postoji.data as Profil;
  const meta = user.user_metadata ?? {};
  const ime = String(meta.ime || meta.full_name || meta.name || (user.email ?? 'Korisnik').split('@')[0]).trim().slice(0, 60) || 'Korisnik';
  const r = await sb.from('oglasnik_profili').insert({ id: user.id, ime }).select('*').single();
  return (r.data as Profil | null) ?? null;
}

/** Poruke baze prevedene za korisnika. */
import { prevedi, type Jezik } from './i18n';

export function porukaGreske(m: string | undefined, j: Jezik = 'hr'): string {
  return prevedi(j, porukaGreskeHr(m));
}

function porukaGreskeHr(m: string | undefined): string {
  const t = m ?? '';
  if (/Invalid login credentials/i.test(t)) return 'Pogrešan e-mail ili lozinka.';
  if (/already registered/i.test(t)) return 'Taj e-mail je već registriran.';
  if (/Email not confirmed/i.test(t)) return 'Potvrdi e-mail adresu (poveznica je u pošti).';
  if (/Password should be/i.test(t)) return 'Lozinka mora imati barem 8 znakova.';
  if (/row-level security/i.test(t)) return 'Nemaš dopuštenje za ovu radnju (račun je možda blokiran).';
  if (/duplicate key.*oglasnik_prijave/i.test(t)) return 'Već si prijavio ovaj oglas.';
  if (/Oglas|Samo administrator/.test(t)) return t;
  if (/provider is not enabled|Unsupported provider/i.test(t)) return 'Prijava Googleom još nije uključena. Prijavi se e-mailom.';
  return t || 'Nešto nije u redu. Pokušaj ponovno.';
}
