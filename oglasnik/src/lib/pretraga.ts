import type { Filteri, Oglas } from '../data/types';
import { normaliziraj, rijeciUpita } from './tekst';

/** Je li oglas javno vidljiv u popisu (aktivan i nije istekao). */
export const jeAktivan = (o: Oglas, sada = Date.now()) =>
  o.status === 'aktivan' && new Date(o.istjece).getTime() > sada;

export const jeIstekao = (o: Oglas, sada = Date.now()) =>
  o.status === 'aktivan' && new Date(o.istjece).getTime() <= sada;

export function tekstZaPretragu(o: Pick<Oglas, 'naslov' | 'opis' | 'grad' | 'polja'>) {
  return normaliziraj(`${o.naslov} ${o.opis} ${o.grad} ${Object.values(o.polja).join(' ')}`);
}

/** Isti filteri kao upit na bazu, za lokalni način i testove. */
export function odgovara(o: Oglas, f: Filteri, sada = Date.now()): boolean {
  if (!jeAktivan(o, sada)) return false;
  if (f.korisnik && o.korisnik_id !== f.korisnik) return false;
  if (f.kategorija && o.kategorija !== f.kategorija) return false;
  if (f.zupanija && o.zupanija !== f.zupanija) return false;
  if (f.stanje && o.stanje !== f.stanje) return false;
  if (f.grad && !normaliziraj(o.grad).includes(normaliziraj(f.grad))) return false;
  if (f.cijenaOd != null && (o.cijena == null || o.cijena < f.cijenaOd)) return false;
  if (f.cijenaDo != null && (o.cijena == null || o.cijena > f.cijenaDo)) return false;
  for (const [k, v] of Object.entries(f.polja ?? {})) {
    if (v && normaliziraj(o.polja[k] ?? '') !== normaliziraj(v)) return false;
  }
  const rijeci = rijeciUpita(f.q);
  if (rijeci.length) {
    const t = tekstZaPretragu(o);
    if (!rijeci.every((w) => t.includes(w))) return false;
  }
  return true;
}

export function sortiraj(list: Oglas[], sort: Filteri['sort']): Oglas[] {
  const out = [...list];
  const novije = (a: Oglas, b: Oglas) => b.objavljeno.localeCompare(a.objavljeno);
  if (sort === 'cijena_rastuce' || sort === 'cijena_padajuce') {
    const smjer = sort === 'cijena_rastuce' ? 1 : -1;
    out.sort((a, b) => {
      // "Dogovor" (bez cijene) uvijek na kraj.
      if (a.cijena == null && b.cijena == null) return novije(a, b);
      if (a.cijena == null) return 1;
      if (b.cijena == null) return -1;
      return (a.cijena - b.cijena) * smjer || novije(a, b);
    });
  } else {
    out.sort(novije);
  }
  return out;
}

/** Filteri ↔ adresa (?q=…&kategorija=…), da se pretraga može podijeliti. */
export function filteriIzAdrese(params: URLSearchParams): Filteri {
  const broj = (k: string) => {
    const v = params.get(k);
    if (v == null || v === '') return undefined;
    const n = Number(v.replace(',', '.'));
    return Number.isFinite(n) ? n : undefined;
  };
  const polja: Record<string, string> = {};
  params.forEach((v, k) => {
    if (k.startsWith('p_') && v) polja[k.slice(2)] = v;
  });
  const sort = params.get('sort');
  return {
    q: params.get('q') || undefined,
    kategorija: params.get('kategorija') || undefined,
    cijenaOd: broj('od'),
    cijenaDo: broj('do'),
    zupanija: params.get('zupanija') || undefined,
    grad: params.get('grad') || undefined,
    stanje: params.get('stanje') || undefined,
    polja,
    sort:
      sort === 'cijena_rastuce' || sort === 'cijena_padajuce' ? sort : 'najnovije',
  };
}

export function adresaIzFiltera(f: Filteri): string {
  const p = new URLSearchParams();
  if (f.q) p.set('q', f.q);
  if (f.kategorija) p.set('kategorija', f.kategorija);
  if (f.cijenaOd != null) p.set('od', String(f.cijenaOd));
  if (f.cijenaDo != null) p.set('do', String(f.cijenaDo));
  if (f.zupanija) p.set('zupanija', f.zupanija);
  if (f.grad) p.set('grad', f.grad);
  if (f.stanje) p.set('stanje', f.stanje);
  for (const [k, v] of Object.entries(f.polja ?? {})) if (v) p.set(`p_${k}`, v);
  if (f.sort && f.sort !== 'najnovije') p.set('sort', f.sort);
  const s = p.toString();
  return s ? `?${s}` : '';
}
