// Lokalni (demo) način: sve se sprema u IndexedDB ovog preglednika.
// Koristi se kad build nema Supabase postavke i u testovima. Pravila su
// ista kao u bazi (vlasnik, blokirani korisnici, admin), da se ponašanje
// aplikacije ne razlikuje.
import { ISTEK_DANA, PO_STRANICI } from '../config/app';
import { jeAktivan, odgovara, sortiraj } from '../lib/pretraga';
import { ocistiNacrt, provjeriOglas } from '../lib/provjera';
import * as db from './idb';
import {
  GreskaKorisnika,
  type Backend,
  type Filteri,
  type Kontakt,
  type NacrtOglasa,
  type Oglas,
  type Poruka,
  type Prijava,
  type Profil,
  type Razgovor,
  type RazgovorSazetak,
  type SlikaZaSpremanje,
} from './types';

interface LokalniKorisnik extends Profil {
  email: string;
  lozinka: string; // SHA-256
  telefon: string | null;
}
interface Favorit {
  id: string;
  korisnik_id: string;
  oglas_id: string;
  kreirano: string;
}
interface LokalniRazgovor extends Razgovor {
  procitao: Record<string, string>;
}

const SESIJA = 'oglasnik_sesija';
const dan = 86400000;

const uuid = () =>
  globalThis.crypto?.randomUUID?.() ??
  `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;

async function hash(s: string) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

function blobUrl(b: Blob): Promise<string> {
  return new Promise((ok, greska) => {
    const r = new FileReader();
    r.onload = () => ok(r.result as string);
    r.onerror = () => greska(r.error);
    r.readAsDataURL(b);
  });
}

function bezTajni(k: LokalniKorisnik): Profil {
  const { id, ime, grad, registriran, blokiran, admin } = k;
  return { id, ime, grad, registriran, blokiran, admin };
}

export class LokalniBackend implements Backend {
  readonly nacin = 'lokalno' as const;
  private slusatelji = new Set<() => void>();
  constructor(private sat: () => number = Date.now) {}

  private sada = () => new Date(this.sat()).toISOString();

  private get sesija(): string | null {
    try {
      return localStorage.getItem(SESIJA);
    } catch {
      return null;
    }
  }
  private set sesija(id: string | null) {
    try {
      if (id) localStorage.setItem(SESIJA, id);
      else localStorage.removeItem(SESIJA);
    } catch {
      /* privatni način: sesija samo u memoriji */
    }
    this.slusatelji.forEach((cb) => cb());
  }

  private async ja(): Promise<LokalniKorisnik> {
    const id = this.sesija;
    const k = id ? await db.jedan<LokalniKorisnik>('korisnici', id) : undefined;
    if (!k) throw new GreskaKorisnika('Prijavi se za nastavak.');
    return k;
  }
  private async jaAktivan() {
    const k = await this.ja();
    if (k.blokiran) throw new GreskaKorisnika('Račun je blokiran.');
    return k;
  }
  private async jaAdmin() {
    const k = await this.ja();
    if (!k.admin) throw new GreskaKorisnika('Samo za administratore.');
    return k;
  }

  async trenutni() {
    const id = this.sesija;
    const k = id ? await db.jedan<LokalniKorisnik>('korisnici', id) : undefined;
    return k ? bezTajni(k) : null;
  }
  naPromjenuPrijave(cb: () => void) {
    this.slusatelji.add(cb);
    return () => this.slusatelji.delete(cb);
  }

  async registracija(email: string, lozinka: string, ime: string) {
    email = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new GreskaKorisnika('Upiši ispravan e-mail.');
    if (lozinka.length < 8) throw new GreskaKorisnika('Lozinka mora imati barem 8 znakova.');
    if (ime.trim().length < 2) throw new GreskaKorisnika('Upiši ime.');
    const svi = await db.sve<LokalniKorisnik>('korisnici');
    if (svi.some((k) => k.email === email)) throw new GreskaKorisnika('Taj e-mail je već registriran.');
    const k: LokalniKorisnik = {
      id: uuid(),
      email,
      lozinka: await hash(lozinka),
      ime: ime.trim(),
      grad: null,
      telefon: null,
      registriran: this.sada(),
      blokiran: false,
      // Demo način: prvi registrirani korisnik je administrator.
      admin: svi.length === 0,
    };
    await db.spremi('korisnici', k);
    this.sesija = k.id;
    return { potvrdaEmaila: false };
  }

  async prijava(email: string, lozinka: string) {
    email = email.trim().toLowerCase();
    const h = await hash(lozinka);
    const k = (await db.sve<LokalniKorisnik>('korisnici')).find((x) => x.email === email);
    if (!k || k.lozinka !== h) throw new GreskaKorisnika('Pogrešan e-mail ili lozinka.');
    this.sesija = k.id;
  }

  async prijavaGoogle() {
    throw new GreskaKorisnika('Prijava s Googleom radi tek kad je spojena baza.');
  }

  async odjava() {
    this.sesija = null;
  }

  async spremiProfil(p: { ime: string; grad: string | null; telefon: string | null }) {
    const k = await this.ja();
    if (p.ime.trim().length < 2) throw new GreskaKorisnika('Upiši ime.');
    await db.spremi('korisnici', {
      ...k,
      ime: p.ime.trim(),
      grad: p.grad?.trim() || null,
      telefon: p.telefon?.trim() || null,
    });
    this.slusatelji.forEach((cb) => cb());
  }

  async mojTelefon() {
    return (await this.ja()).telefon;
  }

  async profil(id: string) {
    const k = await db.jedan<LokalniKorisnik>('korisnici', id);
    return k ? bezTajni(k) : null;
  }

  // ---------- Oglasi ----------

  private async vidljivi(): Promise<Oglas[]> {
    const ja = this.sesija;
    const admin = ja ? (await db.jedan<LokalniKorisnik>('korisnici', ja))?.admin : false;
    return (await db.sve<Oglas>('oglasi')).filter(
      (o) =>
        admin ||
        o.status === 'aktivan' ||
        o.status === 'prodano' ||
        (o.status === 'uklonjen' && o.korisnik_id === ja),
    );
  }

  async trazi(f: Filteri, stranica: number) {
    const sada = this.sat();
    const svi = sortiraj(
      (await db.sve<Oglas>('oglasi')).filter((o) => odgovara(o, f, sada)),
      f.sort,
    );
    return {
      stavke: svi.slice(stranica * PO_STRANICI, (stranica + 1) * PO_STRANICI),
      ukupno: svi.length,
    };
  }

  async oglas(id: string) {
    return (await this.vidljivi()).find((o) => o.id === id) ?? null;
  }

  async mojiOglasi() {
    const ja = await this.ja();
    return sortiraj(
      (await db.sve<Oglas>('oglasi')).filter((o) => o.korisnik_id === ja.id && o.status !== 'obrisan'),
      'najnovije',
    );
  }

  async brojAktivnihOglasa(korisnikId: string) {
    const sada = this.sat();
    return (await db.sve<Oglas>('oglasi')).filter(
      (o) => o.korisnik_id === korisnikId && jeAktivan(o, sada),
    ).length;
  }

  private async mojOglas(id: string) {
    const ja = await this.ja();
    const o = await db.jedan<Oglas>('oglasi', id);
    if (!o || o.korisnik_id !== ja.id || o.status === 'obrisan') throw new GreskaKorisnika('Oglas nije pronađen.');
    return o;
  }

  async spremiOglas(nacrt: NacrtOglasa, slike: SlikaZaSpremanje[], id?: string) {
    const ja = await this.jaAktivan();
    const greske = provjeriOglas(nacrt, slike.length);
    if (Object.keys(greske).length) throw new GreskaKorisnika(Object.values(greske)[0]);
    const n = ocistiNacrt(nacrt);
    const velike: string[] = [];
    const male: string[] = [];
    for (const s of slike) {
      if (s.vrsta === 'postojeca') {
        velike.push(s.url);
        male.push(s.mala);
      } else {
        velike.push(await blobUrl(s.velika));
        male.push(await blobUrl(s.mala));
      }
    }
    const prije = id ? await this.mojOglas(id) : null;
    if (prije?.status === 'uklonjen') throw new GreskaKorisnika('Uklonjeni oglas ne može se mijenjati.');
    const sada = this.sat();
    const o: Oglas = {
      id: prije?.id ?? uuid(),
      korisnik_id: ja.id,
      ...n,
      slike: velike,
      slike_male: male,
      vrsta_prodaje: 'fiksna_cijena',
      status: prije?.status ?? 'aktivan',
      objavljeno: prije?.objavljeno ?? new Date(sada).toISOString(),
      istjece: prije?.istjece ?? new Date(sada + ISTEK_DANA * dan).toISOString(),
      prodano_datum: prije?.prodano_datum ?? null,
      prodano_cijena: prije?.prodano_cijena ?? null,
      uklonjeno_razlog: null,
    };
    return db.spremi('oglasi', o);
  }

  async produlji(id: string) {
    await this.jaAktivan();
    const o = await this.mojOglas(id);
    if (o.status !== 'aktivan') throw new GreskaKorisnika('Produljiti se može samo aktivan oglas.');
    await db.spremi('oglasi', { ...o, istjece: new Date(this.sat() + ISTEK_DANA * dan).toISOString() });
  }

  async oznaciProdano(id: string, cijena: number | null) {
    const o = await this.mojOglas(id);
    if (o.status === 'uklonjen') throw new GreskaKorisnika('Oglas je uklonjen.');
    if (cijena != null && (!Number.isFinite(cijena) || cijena < 0)) throw new GreskaKorisnika('Neispravna cijena.');
    await db.spremi('oglasi', {
      ...o,
      status: 'prodano',
      prodano_datum: this.sada(),
      prodano_cijena: cijena,
    });
  }

  async obrisi(id: string) {
    const o = await this.mojOglas(id);
    // Meko brisanje: oglas nestaje svima osim admina, a kontakti i
    // podaci o prodaji ostaju za statistiku.
    await db.spremi('oglasi', { ...o, status: 'obrisan' as const });
    for (const f of await db.sve<Favorit>('favoriti')) if (f.oglas_id === id) await db.izbrisi('favoriti', f.id);
  }

  // ---------- Favoriti ----------

  private async mojiFavoriti() {
    const id = this.sesija;
    if (!id) return [];
    return (await db.sve<Favorit>('favoriti')).filter((f) => f.korisnik_id === id);
  }

  async favoritIds() {
    return new Set((await this.mojiFavoriti()).map((f) => f.oglas_id));
  }

  async favoriti() {
    const f = await this.mojiFavoriti();
    const svi = await this.vidljivi();
    return f
      .sort((a, b) => b.kreirano.localeCompare(a.kreirano))
      .map((x) => svi.find((o) => o.id === x.oglas_id))
      .filter((o): o is Oglas => !!o);
  }

  async postaviFavorit(oglasId: string, da: boolean) {
    const ja = await this.ja();
    const id = `${ja.id}:${oglasId}`;
    if (da) await db.spremi<Favorit>('favoriti', { id, korisnik_id: ja.id, oglas_id: oglasId, kreirano: this.sada() });
    else await db.izbrisi('favoriti', id);
  }

  // ---------- Poruke ----------

  private async sazetak(r: LokalniRazgovor, jaId: string): Promise<RazgovorSazetak> {
    const o = await db.jedan<Oglas>('oglasi', r.oglas_id);
    const drugi = r.kupac_id === jaId ? r.prodavatelj_id : r.kupac_id;
    const poruke = (await db.sve<Poruka>('poruke'))
      .filter((p) => p.razgovor_id === r.id)
      .sort((a, b) => a.poslano.localeCompare(b.poslano));
    const zadnja = poruke[poruke.length - 1] ?? null;
    return {
      razgovor: r,
      oglas: o ? { id: o.id, naslov: o.naslov, slike_male: o.slike_male, cijena: o.cijena, status: o.status } : null,
      sugovornik: await this.profil(drugi),
      zadnja,
      neprocitano: !!zadnja && zadnja.posiljatelj_id !== jaId && (r.procitao[jaId] ?? '') < zadnja.poslano,
    };
  }

  async razgovori() {
    const ja = await this.ja();
    const moji = (await db.sve<LokalniRazgovor>('razgovori')).filter(
      (r) => r.kupac_id === ja.id || r.prodavatelj_id === ja.id,
    );
    moji.sort((a, b) => b.zadnja_poruka.localeCompare(a.zadnja_poruka));
    return Promise.all(moji.map((r) => this.sazetak(r, ja.id)));
  }

  private async mojRazgovor(id: string) {
    const ja = await this.ja();
    const r = await db.jedan<LokalniRazgovor>('razgovori', id);
    if (!r || (r.kupac_id !== ja.id && r.prodavatelj_id !== ja.id)) return null;
    return { ja, r };
  }

  async razgovor(id: string) {
    const x = await this.mojRazgovor(id);
    if (!x) return null;
    const poruke = (await db.sve<Poruka>('poruke'))
      .filter((p) => p.razgovor_id === id)
      .sort((a, b) => a.poslano.localeCompare(b.poslano));
    return { sazetak: await this.sazetak(x.r, x.ja.id), poruke };
  }

  async postojeciRazgovor(oglasId: string) {
    const id = this.sesija;
    if (!id) return null;
    const r = (await db.sve<LokalniRazgovor>('razgovori')).find(
      (x) => x.oglas_id === oglasId && x.kupac_id === id,
    );
    return r?.id ?? null;
  }

  private async kontakt(oglasId: string, korisnikId: string, vrsta: Kontakt['vrsta']) {
    await db.spremi<Kontakt>('kontakti', { id: uuid(), oglas_id: oglasId, korisnik_id: korisnikId, vrsta, kreirano: this.sada() });
  }

  async zapocniRazgovor(oglasId: string, tekst: string) {
    const ja = await this.jaAktivan();
    const o = await db.jedan<Oglas>('oglasi', oglasId);
    if (!o || !jeAktivan(o, this.sat())) throw new GreskaKorisnika('Oglas više nije aktivan.');
    if (o.korisnik_id === ja.id) throw new GreskaKorisnika('Ne možeš pisati sam sebi.');
    let id = await this.postojeciRazgovor(oglasId);
    if (!id) {
      const r: LokalniRazgovor = {
        id: uuid(),
        oglas_id: oglasId,
        kupac_id: ja.id,
        prodavatelj_id: o.korisnik_id,
        kreirano: this.sada(),
        zadnja_poruka: this.sada(),
        procitao: {},
      };
      await db.spremi('razgovori', r);
      await this.kontakt(oglasId, ja.id, 'poruka');
      id = r.id;
    }
    await this.posalji(id, tekst);
    return id;
  }

  async posalji(razgovorId: string, tekst: string) {
    const ja = await this.jaAktivan();
    tekst = tekst.trim();
    if (!tekst) throw new GreskaKorisnika('Poruka je prazna.');
    if (tekst.length > 2000) throw new GreskaKorisnika('Poruka može imati najviše 2000 znakova.');
    const x = await this.mojRazgovor(razgovorId);
    if (!x) throw new GreskaKorisnika('Razgovor nije pronađen.');
    const p: Poruka = { id: uuid(), razgovor_id: razgovorId, posiljatelj_id: ja.id, tekst, poslano: this.sada() };
    await db.spremi('poruke', p);
    await db.spremi('razgovori', { ...x.r, zadnja_poruka: p.poslano, procitao: { ...x.r.procitao, [ja.id]: p.poslano } });
  }

  async oznaciProcitano(razgovorId: string) {
    const x = await this.mojRazgovor(razgovorId);
    if (x) await db.spremi('razgovori', { ...x.r, procitao: { ...x.r.procitao, [x.ja.id]: this.sada() } });
  }

  async telefon(oglasId: string) {
    const ja = await this.jaAktivan();
    const o = await db.jedan<Oglas>('oglasi', oglasId);
    if (!o || !o.prikazi_telefon || o.status === 'uklonjen') return null;
    const k = await db.jedan<LokalniKorisnik>('korisnici', o.korisnik_id);
    if (!k?.telefon) return null;
    if (ja.id !== o.korisnik_id) await this.kontakt(oglasId, ja.id, 'telefon');
    return k.telefon;
  }

  async kontakti(oglasId: string) {
    await this.mojOglas(oglasId);
    return (await db.sve<Kontakt>('kontakti'))
      .filter((k) => k.oglas_id === oglasId)
      .sort((a, b) => b.kreirano.localeCompare(a.kreirano));
  }

  // ---------- Prijave i moderacija ----------

  async prijaviOglas(oglasId: string, razlog: Prijava['razlog'], napomena: string) {
    const ja = await this.ja();
    const id = `${ja.id}:${oglasId}`;
    if (await db.jedan('prijave', id)) throw new GreskaKorisnika('Već si prijavio ovaj oglas.');
    await db.spremi<Prijava>('prijave', {
      id,
      oglas_id: oglasId,
      prijavitelj_id: ja.id,
      razlog,
      napomena: napomena.trim().slice(0, 1000),
      kreirano: this.sada(),
      status: 'otvorena',
    });
  }

  async prijave() {
    await this.jaAdmin();
    const oglasi = await db.sve<Oglas>('oglasi');
    return (await db.sve<Prijava>('prijave'))
      .sort((a, b) => b.kreirano.localeCompare(a.kreirano))
      .map((p) => {
        const o = oglasi.find((x) => x.id === p.oglas_id);
        return { ...p, oglas: o ? { id: o.id, naslov: o.naslov, korisnik_id: o.korisnik_id, status: o.status } : null };
      });
  }

  async rijesiPrijavu(id: string) {
    await this.jaAdmin();
    const p = await db.jedan<Prijava>('prijave', id);
    if (p) await db.spremi('prijave', { ...p, status: 'rijesena' as const, oglas: undefined });
  }

  async ukloniOglas(id: string, razlog: string) {
    await this.jaAdmin();
    const o = await db.jedan<Oglas>('oglasi', id);
    if (o) await db.spremi('oglasi', { ...o, status: 'uklonjen' as const, uklonjeno_razlog: razlog || null });
  }

  async blokiraj(korisnikId: string, blokiran: boolean) {
    const ja = await this.jaAdmin();
    if (ja.id === korisnikId) throw new GreskaKorisnika('Ne možeš blokirati sebe.');
    const k = await db.jedan<LokalniKorisnik>('korisnici', korisnikId);
    if (k) await db.spremi('korisnici', { ...k, blokiran });
  }

  async korisnici() {
    await this.jaAdmin();
    return (await db.sve<LokalniKorisnik>('korisnici'))
      .map(bezTajni)
      .sort((a, b) => b.registriran.localeCompare(a.registriran));
  }
}
