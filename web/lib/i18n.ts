import { EN } from './prijevodi-en';

/** Jezici stranice. Hrvatski je na postojećim adresama, engleski pod /en. */
export type Jezik = 'hr' | 'en';
export const JEZICI: Jezik[] = ['hr', 'en'];
export const jezik = (s: string | undefined): Jezik => (s === 'en' ? 'en' : 'hr');
export const LOCALE: Record<Jezik, string> = { hr: 'hr-HR', en: 'en-GB' };
export const OG_LOCALE: Record<Jezik, string> = { hr: 'hr_HR', en: 'en_GB' };

/** Prijevod: ključ je hrvatski tekst; {ime} se zamjenjuje vrijednostima. */
export function prevedi(j: Jezik, s: string, v?: Record<string, string | number>): string {
  let r = j === 'en' ? (EN[s] ?? s) : s;
  if (v) for (const [k, x] of Object.entries(v)) r = r.split(`{${k}}`).join(String(x));
  return r;
}
export type T = (s: string, v?: Record<string, string | number>) => string;
export const prevodilac = (j: Jezik): T => (s, v) => prevedi(j, s, v);

/** Adresa na jeziku: put('en', '/oglasi') → '/en/oglasi'. */
export function put(j: Jezik, p: string): string {
  if (j === 'hr') return p;
  return p === '/' ? '/en' : `/en${p}`;
}

/** Putanja bez jezičnog prefiksa (/en/oglasi → /oglasi; /hr/... je interna adresa kod generiranja). */
export function bezJezika(p: string): string {
  if (p === '/en' || p === '/hr') return '/';
  return p.startsWith('/en/') || p.startsWith('/hr/') ? p.slice(3) : p;
}

/** canonical + hreflang za stranicu (put je hrvatska adresa). */
export function alternative(j: Jezik, p: string) {
  return { canonical: put(j, p), languages: { hr: p, en: put('en', p), 'x-default': p } };
}
