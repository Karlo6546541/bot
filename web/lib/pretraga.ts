import type { Filteri, Oglas, Sortiranje } from './types';
import { jeDrzava } from './lokacije';
import { podkategorija, sekcija } from './kategorije';
import { normaliziraj, rijeciUpita } from './tekst';

export const jeAktivan = (o: Oglas, sada = Date.now()) =>
  o.status === 'aktivan' && new Date(o.istjece).getTime() > sada;
export const jeIstekao = (o: Oglas, sada = Date.now()) =>
  o.status === 'aktivan' && new Date(o.istjece).getTime() <= sada;

const prvi = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
const broj = (v: string | undefined) => {
  if (v == null || v.trim() === '') return undefined;
  const n = Number(v.replace(',', '.'));
  return Number.isFinite(n) && n >= 0 ? n : undefined;
};

/** Filteri iz adrese (?q=…&drzava=HR&zupanija=…). Nepoznate vrijednosti se odbacuju. */
export function filteriIzUpita(sp: Record<string, string | string[] | undefined>, kat?: string, sek?: string): Filteri {
  const polja: Record<string, string> = {};
  for (const [k, v] of Object.entries(sp)) {
    const x = prvi(v);
    if (k.startsWith('p_') && x && /^[a-z_]+$/.test(k.slice(2))) polja[k.slice(2)] = x.slice(0, 80);
  }
  const sort = prvi(sp.sort);
  const drzava = prvi(sp.drzava);
  const kategorijaSlug = kat ?? prvi(sp.kategorija);
  const sekcijaSlug = sek ?? prvi(sp.sekcija);
  return {
    q: prvi(sp.q)?.slice(0, 100) || undefined,
    kategorija: podkategorija(kategorijaSlug) ? kategorijaSlug : undefined,
    sekcija: sekcija(sekcijaSlug) ? sekcijaSlug : undefined,
    cijenaOd: broj(prvi(sp.od)),
    cijenaDo: broj(prvi(sp.do)),
    drzava: jeDrzava(drzava) ? drzava : undefined,
    zupanija: prvi(sp.zupanija)?.slice(0, 60) || undefined,
    grad: prvi(sp.grad)?.slice(0, 60) || undefined,
    stanje: prvi(sp.stanje) || undefined,
    polja,
    sort: sort === 'cijena_rastuce' || sort === 'cijena_padajuce' ? sort : 'najnovije',
  };
}

/** Filteri → upit za adresu (bez praznih vrijednosti), npr. za poveznice i paginaciju. */
export function upitIzFiltera(f: Filteri, stranica?: number): string {
  const p = new URLSearchParams();
  if (f.q) p.set('q', f.q);
  if (f.sekcija) p.set('sekcija', f.sekcija);
  if (f.kategorija) p.set('kategorija', f.kategorija);
  if (f.cijenaOd != null) p.set('od', String(f.cijenaOd));
  if (f.cijenaDo != null) p.set('do', String(f.cijenaDo));
  if (f.drzava) p.set('drzava', f.drzava);
  if (f.zupanija) p.set('zupanija', f.zupanija);
  if (f.grad) p.set('grad', f.grad);
  if (f.stanje) p.set('stanje', f.stanje);
  for (const [k, v] of Object.entries(f.polja ?? {})) if (v) p.set(`p_${k}`, v);
  if (f.sort && f.sort !== 'najnovije') p.set('sort', f.sort);
  if (stranica && stranica > 1) p.set('stranica', String(stranica));
  const s = p.toString();
  return s ? `?${s}` : '';
}

export function brojStranice(sp: Record<string, string | string[] | undefined>): number {
  const n = Math.floor(Number(prvi(sp.stranica) ?? 1));
  return Number.isFinite(n) && n >= 1 && n <= 500 ? n : 1;
}

export function tekstZaPretragu(o: Pick<Oglas, 'naslov' | 'opis' | 'grad' | 'zupanija' | 'polja'>) {
  return normaliziraj(`${o.naslov} ${o.opis} ${o.grad} ${o.zupanija ?? ''} ${Object.values(o.polja).join(' ')}`);
}

/** Isti filteri kao upit na bazu (za testove i demo). */
export function odgovara(o: Oglas, f: Filteri, sada = Date.now()): boolean {
  if (!jeAktivan(o, sada)) return false;
  if (f.korisnik && o.korisnik_id !== f.korisnik) return false;
  if (f.kategorija && o.kategorija !== f.kategorija) return false;
  if (f.sekcija && podkategorija(o.kategorija)?.sekcija !== f.sekcija) return false;
  if (f.drzava && o.drzava !== f.drzava) return false;
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

export function sortiraj(list: Oglas[], sort: Sortiranje | undefined): Oglas[] {
  const out = [...list];
  const novije = (a: Oglas, b: Oglas) => b.objavljeno.localeCompare(a.objavljeno);
  if (sort === 'cijena_rastuce' || sort === 'cijena_padajuce') {
    const smjer = sort === 'cijena_rastuce' ? 1 : -1;
    out.sort((a, b) => {
      if (a.cijena == null && b.cijena == null) return novije(a, b);
      if (a.cijena == null) return 1;
      if (b.cijena == null) return -1;
      return (a.cijena - b.cijena) * smjer || novije(a, b);
    });
  } else out.sort(novije);
  return out;
}
