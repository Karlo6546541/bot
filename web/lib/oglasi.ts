// Upiti prema bazi (vrijede za svaki Supabase klijent: javni, poslužiteljski, preglednik).
import type { SupabaseClient } from '@supabase/supabase-js';
import { PO_STRANICI } from './config';
import { sekcija } from './kategorije';
import { normaliziraj, rijeciUpita } from './tekst';
import type { Filteri, Kontakt, Oglas, Poruka, Prijava, Profil, Razgovor } from './types';

export const OGLAS_STUPCI =
  'id,korisnik_id,naslov,kategorija,opis,cijena,drzava,zupanija,grad,stanje,polja,slike,slike_male,prikazi_telefon,vrsta_prodaje,status,objavljeno,azurirano,istjece,prodano_datum,prodano_cijena,uklonjeno_razlog';
const KARTICA_STUPCI = 'id,naslov,kategorija,cijena,drzava,zupanija,grad,stanje,slike_male,status,objavljeno,istjece,korisnik_id';

export type OglasKartica = Pick<
  Oglas,
  'id' | 'naslov' | 'kategorija' | 'cijena' | 'drzava' | 'zupanija' | 'grad' | 'stanje' | 'slike_male' | 'status' | 'objavljeno' | 'istjece' | 'korisnik_id'
>;

export interface Stranica<T> {
  stavke: T[];
  ukupno: number;
}

/** Javni popis: aktivni oglasi koji nisu istekli, uz filtere, sortiranje i straničenje. */
export async function traziOglase(
  sb: SupabaseClient | null,
  f: Filteri,
  stranica = 1,
  koliko = PO_STRANICI,
): Promise<Stranica<OglasKartica>> {
  if (!sb) return { stavke: [], ukupno: 0 };
  let q = sb
    .from('oglasnik_oglasi')
    .select(KARTICA_STUPCI, { count: 'exact' })
    .eq('status', 'aktivan')
    .gt('istjece', new Date().toISOString());
  if (f.korisnik) q = q.eq('korisnik_id', f.korisnik);
  if (f.kategorija) q = q.eq('kategorija', f.kategorija);
  else if (f.sekcija) q = q.in('kategorija', (sekcija(f.sekcija)?.podkategorije ?? []).map((p) => p.slug));
  if (f.drzava) q = q.eq('drzava', f.drzava);
  if (f.zupanija) q = q.eq('zupanija', f.zupanija);
  if (f.stanje) q = q.eq('stanje', f.stanje);
  if (f.grad) q = q.like('grad_n', `%${normaliziraj(f.grad).replace(/[%_\\*]/g, '')}%`);
  if (f.cijenaOd != null) q = q.gte('cijena', f.cijenaOd);
  if (f.cijenaDo != null) q = q.lte('cijena', f.cijenaDo);
  for (const [k, v] of Object.entries(f.polja ?? {})) {
    if (v && /^[a-z_]+$/.test(k)) q = q.eq(`polja->>${k}`, v);
  }
  for (const w of rijeciUpita(f.q)) q = q.like('pretraga', `%${w}%`);
  if (f.sort === 'cijena_rastuce' || f.sort === 'cijena_padajuce') {
    q = q.order('cijena', { ascending: f.sort === 'cijena_rastuce', nullsFirst: false });
  }
  q = q.order('objavljeno', { ascending: false });
  const od = (stranica - 1) * koliko;
  const r = await q.range(od, od + koliko - 1);
  if (r.error) throw new Error(r.error.message);
  return { stavke: (r.data ?? []) as unknown as OglasKartica[], ukupno: r.count ?? 0 };
}

export async function dohvatiOglas(sb: SupabaseClient | null, id: string): Promise<Oglas | null> {
  if (!sb || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  const r = await sb.from('oglasnik_oglasi').select(OGLAS_STUPCI).eq('id', id).maybeSingle();
  if (r.error) throw new Error(r.error.message);
  return (r.data as unknown as Oglas | null) ?? null;
}

/** Slični oglasi: ista kategorija, bez trenutnog (unutarnje povezivanje za SEO). */
export async function slicniOglasi(sb: SupabaseClient | null, o: Pick<Oglas, 'id' | 'kategorija'>, n = 8) {
  if (!sb) return [] as OglasKartica[];
  const r = await sb
    .from('oglasnik_oglasi')
    .select(KARTICA_STUPCI)
    .eq('status', 'aktivan')
    .eq('kategorija', o.kategorija)
    .neq('id', o.id)
    .gt('istjece', new Date().toISOString())
    .order('objavljeno', { ascending: false })
    .limit(n);
  return (r.data ?? []) as unknown as OglasKartica[];
}

export async function dohvatiProfil(sb: SupabaseClient | null, id: string): Promise<Profil | null> {
  if (!sb || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  const r = await sb.from('oglasnik_profili').select('*').eq('id', id).maybeSingle();
  return (r.data as Profil | null) ?? null;
}

export async function brojAktivnih(sb: SupabaseClient | null, korisnikId: string): Promise<number> {
  if (!sb) return 0;
  const r = await sb
    .from('oglasnik_oglasi')
    .select('id', { count: 'exact', head: true })
    .eq('korisnik_id', korisnikId)
    .eq('status', 'aktivan')
    .gt('istjece', new Date().toISOString());
  return r.count ?? 0;
}

/** Svi URL-ovi oglasa za sitemap (do 5000, najnoviji prvi). */
export async function oglasiZaSitemap(sb: SupabaseClient | null) {
  if (!sb) return [] as Pick<Oglas, 'id' | 'naslov' | 'azurirano' | 'objavljeno' | 'slike'>[];
  const r = await sb
    .from('oglasnik_oglasi')
    .select('id,naslov,azurirano,objavljeno,slike')
    .eq('status', 'aktivan')
    .gt('istjece', new Date().toISOString())
    .order('objavljeno', { ascending: false })
    .limit(5000);
  return (r.data ?? []) as unknown as Pick<Oglas, 'id' | 'naslov' | 'azurirano' | 'objavljeno' | 'slike'>[];
}

// ---------- Privatno (prijavljeni korisnik; RLS štiti podatke) ----------

export async function mojiOglasi(sb: SupabaseClient, uid: string): Promise<Oglas[]> {
  const r = await sb
    .from('oglasnik_oglasi')
    .select(OGLAS_STUPCI)
    .eq('korisnik_id', uid)
    .neq('status', 'obrisan')
    .order('objavljeno', { ascending: false });
  if (r.error) throw new Error(r.error.message);
  return (r.data ?? []) as unknown as Oglas[];
}

export async function favoritiOglasi(sb: SupabaseClient, uid: string): Promise<OglasKartica[]> {
  const r = await sb
    .from('oglasnik_favoriti')
    .select(`kreirano, oglas:oglasnik_oglasi(${KARTICA_STUPCI})`)
    .eq('korisnik_id', uid)
    .order('kreirano', { ascending: false });
  const redovi = (r.data ?? []) as unknown as { oglas: OglasKartica | null }[];
  return redovi.map((x) => x.oglas).filter((o): o is OglasKartica => !!o);
}

export async function jeFavorit(sb: SupabaseClient, uid: string, oglasId: string): Promise<boolean> {
  const r = await sb.from('oglasnik_favoriti').select('oglas_id').eq('korisnik_id', uid).eq('oglas_id', oglasId).maybeSingle();
  return !!r.data;
}

export interface RazgovorSazetak {
  razgovor: Razgovor;
  oglas: Pick<Oglas, 'id' | 'naslov' | 'slike_male' | 'cijena' | 'status'> | null;
  sugovornik: Pick<Profil, 'id' | 'ime'> | null;
  zadnja: Poruka | null;
  neprocitano: boolean;
}

export async function razgovori(sb: SupabaseClient, uid: string): Promise<RazgovorSazetak[]> {
  const r = await sb
    .from('oglasnik_razgovori')
    .select('*')
    .or(`kupac_id.eq.${uid},prodavatelj_id.eq.${uid}`)
    .order('zadnja_poruka', { ascending: false })
    .limit(100);
  const redovi = (r.data ?? []) as Razgovor[];
  if (!redovi.length) return [];
  const oglasIds = [...new Set(redovi.map((x) => x.oglas_id))];
  const drugiIds = [...new Set(redovi.map((x) => (x.kupac_id === uid ? x.prodavatelj_id : x.kupac_id)))];
  const [oglasi, profili, poruke] = await Promise.all([
    sb.from('oglasnik_oglasi').select('id,naslov,slike_male,cijena,status').in('id', oglasIds),
    sb.from('oglasnik_profili').select('id,ime').in('id', drugiIds),
    sb
      .from('oglasnik_poruke')
      .select('*')
      .in('razgovor_id', redovi.map((x) => x.id))
      .order('poslano', { ascending: false })
      .limit(redovi.length * 20),
  ]);
  const o = (oglasi.data ?? []) as unknown as NonNullable<RazgovorSazetak['oglas']>[];
  const p = (profili.data ?? []) as Pick<Profil, 'id' | 'ime'>[];
  const m = (poruke.data ?? []) as Poruka[];
  return redovi.map((x) => {
    const zadnja = m.find((y) => y.razgovor_id === x.id) ?? null;
    const procitao = x.kupac_id === uid ? x.kupac_procitao : x.prodavatelj_procitao;
    const drugi = x.kupac_id === uid ? x.prodavatelj_id : x.kupac_id;
    return {
      razgovor: x,
      oglas: o.find((y) => y.id === x.oglas_id) ?? null,
      sugovornik: p.find((y) => y.id === drugi) ?? null,
      zadnja,
      neprocitano: !!zadnja && zadnja.posiljatelj_id !== uid && (procitao ?? '') < zadnja.poslano,
    };
  });
}

export async function razgovorSPorukama(sb: SupabaseClient, uid: string, id: string) {
  const r = await sb.from('oglasnik_razgovori').select('*').eq('id', id).maybeSingle();
  if (!r.data) return null;
  const poruke = await sb.from('oglasnik_poruke').select('*').eq('razgovor_id', id).order('poslano', { ascending: true }).limit(500);
  const sve = await razgovori(sb, uid);
  const sazetak = sve.find((x) => x.razgovor.id === id) ?? null;
  return { sazetak, poruke: (poruke.data ?? []) as Poruka[] };
}

export async function kontaktiOglasa(sb: SupabaseClient, oglasId: string): Promise<Kontakt[]> {
  const r = await sb.from('oglasnik_kontakti').select('*').eq('oglas_id', oglasId).order('kreirano', { ascending: false });
  return (r.data ?? []) as Kontakt[];
}

export async function prijaveZaAdmina(sb: SupabaseClient): Promise<Prijava[]> {
  const r = await sb
    .from('oglasnik_prijave')
    .select('*, oglas:oglasnik_oglasi(id,naslov,korisnik_id,status)')
    .order('kreirano', { ascending: false })
    .limit(200);
  return (r.data ?? []) as unknown as Prijava[];
}

export async function korisniciZaAdmina(sb: SupabaseClient): Promise<Profil[]> {
  const r = await sb.from('oglasnik_profili').select('*').order('registriran', { ascending: false }).limit(200);
  return (r.data ?? []) as Profil[];
}

/** Naslovna fotografija i broj oglasa po podkategoriji (za ekran kategorija). */
export async function pregledKategorija(sb: SupabaseClient | null): Promise<Record<string, { slika: string; broj: number }>> {
  if (!sb) return {};
  const r = await sb
    .from('oglasnik_oglasi')
    .select('kategorija, slike_male')
    .eq('status', 'aktivan')
    .gt('istjece', new Date().toISOString())
    .order('objavljeno', { ascending: false })
    .limit(2000);
  if (r.error) throw new Error(r.error.message);
  const out: Record<string, { slika: string; broj: number }> = {};
  for (const o of (r.data ?? []) as { kategorija: string; slike_male: string[] }[]) {
    const x = (out[o.kategorija] ??= { slika: o.slike_male[0] ?? '', broj: 0 });
    x.broj++;
    if (!x.slika && o.slike_male[0]) x.slika = o.slike_male[0];
  }
  return out;
}
