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

const eur = new Intl.NumberFormat('hr-HR', {
  style: 'currency',
  currency: 'EUR',
  maximumFractionDigits: 2,
  minimumFractionDigits: 0,
});
export const cijenaTekst = (c: number | null) => (c == null ? 'Dogovor' : eur.format(c));

export const datum = (iso: string) =>
  new Date(iso).toLocaleDateString('hr-HR', { day: 'numeric', month: 'numeric', year: 'numeric' });

export function prije(iso: string, sada = Date.now()): string {
  const s = Math.max(0, (sada - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'upravo';
  if (s < 3600) return `prije ${Math.floor(s / 60)} min`;
  if (s < 86400) return `prije ${Math.floor(s / 3600)} h`;
  const d = Math.floor(s / 86400);
  if (d < 30) return d === 1 ? 'jučer' : `prije ${d} dana`;
  return datum(iso);
}

/** Preostali dani do isteka (0 = istječe danas ili je istekao). */
export const danaDoIsteka = (istjece: string, sada = Date.now()) =>
  Math.max(0, Math.ceil((new Date(istjece).getTime() - sada) / 86400000));
