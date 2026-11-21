import { describe, expect, it } from 'vitest';
import type { Oglas } from '../src/data/types';
import { adresaIzFiltera, filteriIzAdrese, odgovara, sortiraj } from '../src/lib/pretraga';
import { ocistiNacrt, provjeriOglas } from '../src/lib/provjera';
import { cijenaTekst, normaliziraj, slug } from '../src/lib/tekst';

const sada = Date.parse('2026-11-20T12:00:00Z');
const oglas = (p: Partial<Oglas>): Oglas => ({
  id: 'x',
  korisnik_id: 'u1',
  naslov: 'Charizard Base Set',
  kategorija: 'kartice',
  opis: 'Odlično očuvana kartica',
  cijena: 100,
  zupanija: 'Grad Zagreb',
  grad: 'Zagreb',
  stanje: 'Dobro',
  polja: { igra: 'Pokémon' },
  slike: ['a'],
  slike_male: ['a'],
  prikazi_telefon: false,
  vrsta_prodaje: 'fiksna_cijena',
  status: 'aktivan',
  objavljeno: '2026-11-19T10:00:00Z',
  istjece: '2026-12-19T10:00:00Z',
  prodano_datum: null,
  prodano_cijena: null,
  uklonjeno_razlog: null,
  ...p,
});

describe('pretraga', () => {
  it('bez dijakritike i velikih slova', () => {
    expect(normaliziraj('Šđčćž POKÉMON')).toBe('sdccz pokemon');
    expect(odgovara(oglas({}), { q: 'charizard ocuvana' }, sada)).toBe(true);
    expect(odgovara(oglas({}), { q: 'pokemon' }, sada)).toBe(true);
    expect(odgovara(oglas({}), { q: 'pikachu' }, sada)).toBe(false);
  });
  it('istekli, prodani i uklonjeni nisu u popisu', () => {
    expect(odgovara(oglas({ istjece: '2026-11-01T00:00:00Z' }), {}, sada)).toBe(false);
    expect(odgovara(oglas({ status: 'prodano' }), {}, sada)).toBe(false);
    expect(odgovara(oglas({ status: 'uklonjen' }), {}, sada)).toBe(false);
  });
  it('filteri: cijena, grad, stanje, polja kategorije', () => {
    const o = oglas({});
    expect(odgovara(o, { cijenaOd: 50, cijenaDo: 150 }, sada)).toBe(true);
    expect(odgovara(o, { cijenaDo: 99 }, sada)).toBe(false);
    expect(odgovara(oglas({ cijena: null }), { cijenaOd: 1 }, sada)).toBe(false);
    expect(odgovara(o, { grad: 'zag' }, sada)).toBe(true);
    expect(odgovara(o, { stanje: 'Novo' }, sada)).toBe(false);
    expect(odgovara(o, { polja: { igra: 'Pokemon' } }, sada)).toBe(true);
    expect(odgovara(o, { polja: { igra: 'Magic' } }, sada)).toBe(false);
  });
  it('sortiranje: dogovor uvijek na kraju', () => {
    const l = [oglas({ id: 'a', cijena: 5 }), oglas({ id: 'b', cijena: null }), oglas({ id: 'c', cijena: 50 })];
    expect(sortiraj(l, 'cijena_rastuce').map((o) => o.id)).toEqual(['a', 'c', 'b']);
    expect(sortiraj(l, 'cijena_padajuce').map((o) => o.id)).toEqual(['c', 'a', 'b']);
  });
  it('filteri se čuvaju u adresi', () => {
    const f = { q: 'kuna', kategorija: 'kovanice-i-novcanice', cijenaDo: 20, polja: { drzava: 'Hrvatska' }, sort: 'cijena_rastuce' as const };
    expect(filteriIzAdrese(new URLSearchParams(adresaIzFiltera(f).slice(1)))).toMatchObject(f);
  });
});

describe('objava', () => {
  const nacrt = {
    naslov: 'Kovanica 5 kuna 1993',
    kategorija: 'kovanice-i-novcanice',
    opis: 'Prvo izdanje, lijepo očuvana.',
    cijena: 12.5,
    zupanija: 'Splitsko-dalmatinska',
    grad: 'Split',
    stanje: 'Dobro',
    polja: { godina: '1993', nepoznato: 'x' },
    prikazi_telefon: false,
  };
  it('ispravan nacrt prolazi, nepoznata polja se brišu', () => {
    expect(provjeriOglas(nacrt, 1)).toEqual({});
    expect(ocistiNacrt(nacrt).polja).toEqual({ godina: '1993' });
  });
  it('fotografija je obavezna, najviše 8', () => {
    expect(provjeriOglas(nacrt, 0).slike).toBeTruthy();
    expect(provjeriOglas(nacrt, 9).slike).toBeTruthy();
  });
  it('greške po polju', () => {
    const g = provjeriOglas({ ...nacrt, naslov: 'a', stanje: 'Super', zupanija: 'X', cijena: -1, polja: { godina: '3000' } }, 1);
    expect(Object.keys(g).sort()).toEqual(['cijena', 'naslov', 'p_godina', 'stanje', 'zupanija']);
  });
  it('tekst', () => {
    expect(cijenaTekst(null)).toBe('Dogovor');
    expect(cijenaTekst(1234.5)).toMatch(/1\.234,5.*€/);
    expect(slug('Pokémon Base Set – 1. izdanje!')).toBe('pokemon-base-set-1-izdanje');
  });
});
