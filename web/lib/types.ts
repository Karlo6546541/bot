import type { RazlogPrijave } from './kategorije';

export interface Profil {
  id: string;
  ime: string;
  grad: string | null;
  drzava: string;
  registriran: string;
  blokiran: boolean;
  admin: boolean;
}

export type StatusOglasa = 'aktivan' | 'prodano' | 'uklonjen' | 'obrisan';
export type Sortiranje = 'najnovije' | 'cijena_rastuce' | 'cijena_padajuce';

export interface Oglas {
  id: string;
  korisnik_id: string;
  naslov: string;
  kategorija: string;
  opis: string;
  cijena: number | null;
  drzava: string;
  zupanija: string | null;
  grad: string;
  stanje: string;
  polja: Record<string, string>;
  slike: string[];
  slike_male: string[];
  prikazi_telefon: boolean;
  vrsta_prodaje: 'fiksna_cijena';
  status: StatusOglasa;
  objavljeno: string;
  azurirano?: string;
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
  drzava: string;
  zupanija: string | null;
  grad: string;
  stanje: string;
  polja: Record<string, string>;
  prikazi_telefon: boolean;
}

export interface Filteri {
  q?: string;
  kategorija?: string;
  sekcija?: string;
  cijenaOd?: number;
  cijenaDo?: number;
  drzava?: string;
  zupanija?: string;
  grad?: string;
  stanje?: string;
  polja?: Record<string, string>;
  sort?: Sortiranje;
  korisnik?: string;
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

export interface Razgovor {
  id: string;
  oglas_id: string;
  kupac_id: string;
  prodavatelj_id: string;
  kreirano: string;
  zadnja_poruka: string;
  kupac_procitao: string | null;
  prodavatelj_procitao: string | null;
}

export interface Poruka {
  id: string;
  razgovor_id: string;
  posiljatelj_id: string;
  tekst: string;
  poslano: string;
}

export interface Kontakt {
  id: string;
  oglas_id: string;
  korisnik_id: string;
  vrsta: 'poruka' | 'telefon';
  kreirano: string;
}
