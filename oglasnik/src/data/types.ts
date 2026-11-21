import type { RazlogPrijave } from '../config/kategorije';

export interface Profil {
  id: string;
  ime: string;
  grad: string | null;
  registriran: string; // ISO datum
  blokiran: boolean;
  admin: boolean;
}

/** Jedina vrsta prodaje u oglasniku; aukcije su u arhivi v0-aukcije. */
export type VrstaProdaje = 'fiksna_cijena';
/** `obrisan`: prodavatelj ga je obrisao; ostaje samo za statistiku (vidi ga admin). */
export type StatusOglasa = 'aktivan' | 'prodano' | 'uklonjen' | 'obrisan';

export interface Oglas {
  id: string;
  korisnik_id: string;
  naslov: string;
  kategorija: string;
  opis: string;
  /** Cijena u EUR; `null` kad je cijena "dogovor". */
  cijena: number | null;
  zupanija: string;
  grad: string;
  stanje: string;
  polja: Record<string, string>;
  slike: string[];
  slike_male: string[];
  prikazi_telefon: boolean;
  vrsta_prodaje: VrstaProdaje;
  status: StatusOglasa;
  objavljeno: string;
  istjece: string;
  prodano_datum: string | null;
  prodano_cijena: number | null;
  uklonjeno_razlog: string | null;
}

export interface NacrtOglasa {
  naslov: string;
  kategorija: string;
  opis: string;
  cijena: number | null;
  zupanija: string;
  grad: string;
  stanje: string;
  polja: Record<string, string>;
  prikazi_telefon: boolean;
}

/** Slika za spremanje: već objavljena (url) ili nova (smanjena u pregledniku). */
export type SlikaZaSpremanje =
  | { vrsta: 'postojeca'; url: string; mala: string }
  | { vrsta: 'nova'; velika: Blob; mala: Blob };

export type Sortiranje = 'najnovije' | 'cijena_rastuce' | 'cijena_padajuce';

export interface Filteri {
  q?: string;
  kategorija?: string;
  cijenaOd?: number;
  cijenaDo?: number;
  zupanija?: string;
  grad?: string;
  stanje?: string;
  polja?: Record<string, string>;
  sort?: Sortiranje;
  korisnik?: string;
}

export interface Razgovor {
  id: string;
  oglas_id: string;
  kupac_id: string;
  prodavatelj_id: string;
  kreirano: string;
  zadnja_poruka: string;
}

export interface Poruka {
  id: string;
  razgovor_id: string;
  posiljatelj_id: string;
  tekst: string;
  poslano: string;
}

export interface RazgovorSazetak {
  razgovor: Razgovor;
  oglas: Pick<Oglas, 'id' | 'naslov' | 'slike_male' | 'cijena' | 'status'> | null;
  sugovornik: Profil | null;
  zadnja: Poruka | null;
  neprocitano: boolean;
}

export interface Prijava {
  id: string;
  oglas_id: string;
  prijavitelj_id: string;
  razlog: RazlogPrijave;
  napomena: string;
  kreirano: string;
  status: 'otvorena' | 'rijesena';
  oglas?: Pick<Oglas, 'id' | 'naslov' | 'korisnik_id' | 'status'> | null;
}

export interface Kontakt {
  id: string;
  oglas_id: string;
  korisnik_id: string;
  vrsta: 'poruka' | 'telefon';
  kreirano: string;
}

export interface Stranica<T> {
  stavke: T[];
  ukupno: number;
}

export interface Backend {
  readonly nacin: 'lokalno' | 'supabase';
  // Prijava
  trenutni(): Promise<Profil | null>;
  naPromjenuPrijave(cb: () => void): () => void;
  registracija(email: string, lozinka: string, ime: string): Promise<{ potvrdaEmaila: boolean }>;
  prijava(email: string, lozinka: string): Promise<void>;
  prijavaGoogle(): Promise<void>;
  odjava(): Promise<void>;
  spremiProfil(p: { ime: string; grad: string | null; telefon: string | null }): Promise<void>;
  mojTelefon(): Promise<string | null>;
  profil(id: string): Promise<Profil | null>;
  // Oglasi
  trazi(f: Filteri, stranica: number): Promise<Stranica<Oglas>>;
  oglas(id: string): Promise<Oglas | null>;
  mojiOglasi(): Promise<Oglas[]>;
  brojAktivnihOglasa(korisnikId: string): Promise<number>;
  spremiOglas(nacrt: NacrtOglasa, slike: SlikaZaSpremanje[], id?: string): Promise<Oglas>;
  produlji(id: string): Promise<void>;
  oznaciProdano(id: string, cijena: number | null): Promise<void>;
  obrisi(id: string): Promise<void>;
  // Favoriti
  favoritIds(): Promise<Set<string>>;
  favoriti(): Promise<Oglas[]>;
  postaviFavorit(oglasId: string, da: boolean): Promise<void>;
  // Poruke i kontakti
  razgovori(): Promise<RazgovorSazetak[]>;
  razgovor(id: string): Promise<{ sazetak: RazgovorSazetak; poruke: Poruka[] } | null>;
  postojeciRazgovor(oglasId: string): Promise<string | null>;
  zapocniRazgovor(oglasId: string, tekst: string): Promise<string>;
  posalji(razgovorId: string, tekst: string): Promise<void>;
  oznaciProcitano(razgovorId: string): Promise<void>;
  telefon(oglasId: string): Promise<string | null>;
  kontakti(oglasId: string): Promise<Kontakt[]>;
  // Prijave i moderacija
  prijaviOglas(oglasId: string, razlog: RazlogPrijave, napomena: string): Promise<void>;
  prijave(): Promise<Prijava[]>;
  rijesiPrijavu(id: string): Promise<void>;
  ukloniOglas(id: string, razlog: string): Promise<void>;
  blokiraj(korisnikId: string, blokiran: boolean): Promise<void>;
  korisnici(): Promise<Profil[]>;
}

export class GreskaKorisnika extends Error {}
