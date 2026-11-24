/** Mala slova bez dijakritike (č→c, đ→d…), za pretragu. Isto radi i baza. */
export function normaliziraj(s: string): string {
  return s
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

/** Riječi upita (bez znakova koji bi smetali upitu na bazu). */
export function rijeciUpita(q: string | undefined): string[] {
  return normaliziraj(q ?? '')
    .split(/[^\p{L}\p{N}]+/u)
    .filter((w) => w.length > 0)
    .slice(0, 8);
}

/** "Pokémon Base Set 1. izdanje" → "pokemon-base-set-1-izdanje" */
export function slug(s: string): string {
  return (
    normaliziraj(s)
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60) || 'oglas'
  );
}

const EUR = {
  hr: new Intl.NumberFormat('hr-HR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2, minimumFractionDigits: 0 }),
  en: new Intl.NumberFormat('en-IE', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2, minimumFractionDigits: 0 }),
};
type J = 'hr' | 'en';
export const cijenaTekst = (c: number | null, j: J = 'hr') => (c == null ? (j === 'en' ? 'Negotiable' : 'Dogovor') : EUR[j].format(c));

export const datum = (iso: string, j: J = 'hr') =>
  new Date(iso).toLocaleDateString(j === 'en' ? 'en-GB' : 'hr-HR', { day: 'numeric', month: 'numeric', year: 'numeric', timeZone: 'Europe/Zagreb' });

export function prije(iso: string, sada = Date.now(), j: J = 'hr'): string {
  const s = Math.max(0, (sada - new Date(iso).getTime()) / 1000);
  const en = j === 'en';
  if (s < 60) return en ? 'just now' : 'upravo';
  if (s < 3600) return en ? `${Math.floor(s / 60)} min ago` : `prije ${Math.floor(s / 60)} min`;
  if (s < 86400) return en ? `${Math.floor(s / 3600)} h ago` : `prije ${Math.floor(s / 3600)} h`;
  const d = Math.floor(s / 86400);
  if (d < 30) return d === 1 ? (en ? 'yesterday' : 'jučer') : en ? `${d} days ago` : `prije ${d} dana`;
  return datum(iso, j);
}

/** Preostali dani do isteka (0 = istječe danas ili je istekao). */
export const danaDoIsteka = (istjece: string, sada = Date.now()) =>
  Math.max(0, Math.ceil((new Date(istjece).getTime() - sada) / 86400000));
