import { describe, expect, it } from 'vitest';
import { filteriIzUpita, odgovara, upitIzFiltera, brojStranice, sortiraj } from '../lib/pretraga';
import { ocistiNacrt, provjeriOglas } from '../lib/provjera';
import { lokacijaTekst, provjeriLokaciju } from '../lib/lokacije';
import { jsonLdOglas, jsonUScript, opisOglasa, putOglasa } from '../lib/seo';
import { cijenaTekst, normaliziraj, slug } from '../lib/tekst';
import type { Oglas } from '../lib/types';

const sada = Date.parse('2026-11-21T12:00:00Z');
const oglas = (p: Partial<Oglas> = {}): Oglas => ({
  id: '11111111-1111-1111-1111-111111111111',
  korisnik_id: 'u1',
  naslov: 'Charizard Base Set 4/102',
  kategorija: 'kartice',
  opis: 'Odlično očuvana holo kartica iz 1999.',
  cijena: 250,
  drzava: 'HR',
  zupanija: 'Grad Zagreb',
  grad: 'Zagreb',
  stanje: 'Dobro',
  polja: { igra: 'Pokémon' },
  slike: ['https://x/a.webp'],
  slike_male: ['https://x/a-m.webp'],
  prikazi_telefon: false,
  vrsta_prodaje: 'fiksna_cijena',
  status: 'aktivan',
  objavljeno: '2026-11-20T10:00:00Z',
  istjece: '2026-12-20T10:00:00Z',
  prodano_datum: null,
  prodano_cijena: null,
  uklonjeno_razlog: null,
  ...p,
});

describe('lokacija', () => {
  it('tekst lokacije izostavlja prazno', () => {
    expect(lokacijaTekst({ drzava: 'HR', zupanija: 'Grad Zagreb', grad: 'Zagreb' })).toBe('Zagreb, Grad Zagreb, Hrvatska');
    expect(lokacijaTekst({ drzava: 'BA', zupanija: null, grad: 'Sarajevo' })).toBe('Sarajevo, Bosna i Hercegovina');
    expect(lokacijaTekst({ drzava: 'HR', zupanija: 'Istarska', grad: 'Pula' }, false)).toBe('Pula, Istarska');
  });
  it('županija je obavezna samo u Hrvatskoj', () => {
    expect(provjeriLokaciju({ drzava: 'HR', zupanija: '', grad: 'Zagreb' }).zupanija).toBeTruthy();
    expect(provjeriLokaciju({ drzava: 'HR', zupanija: 'Pariška', grad: 'Zagreb' }).zupanija).toBeTruthy();
    expect(provjeriLokaciju({ drzava: 'BA', zupanija: '', grad: 'Sarajevo' })).toEqual({});
    expect(provjeriLokaciju({ drzava: 'ZZ', zupanija: '', grad: 'X' })).toMatchObject({ drzava: expect.any(String), grad: expect.any(String) });
  });
});

describe('pretraga i filteri', () => {
  it('upit iz adrese odbacuje nepoznate vrijednosti', () => {
    const f = filteriIzUpita({ q: 'charizard', kategorija: 'nema', drzava: 'XY', od: '-5', do: '300', zupanija: 'Istarska', sort: 'hakiraj' });
    expect(f).toMatchObject({ q: 'charizard', kategorija: undefined, drzava: undefined, cijenaOd: undefined, cijenaDo: 300, zupanija: 'Istarska', sort: 'najnovije' });
  });
  it('filteri se vraćaju u adresu i natrag', () => {
    const f = filteriIzUpita({ q: 'kuna', kategorija: 'kovanice-i-novcanice', drzava: 'HR', zupanija: 'Grad Zagreb', grad: 'Zagreb', p_drzava: 'Hrvatska', sort: 'cijena_rastuce' });
    const url = upitIzFiltera(f, 3);
    expect(url).toContain('drzava=HR');
    expect(url).toContain('stranica=3');
    const iz = filteriIzUpita(Object.fromEntries(new URLSearchParams(url.slice(1))));
    expect(iz).toMatchObject({ q: 'kuna', drzava: 'HR', zupanija: 'Grad Zagreb', grad: 'Zagreb', sort: 'cijena_rastuce' });
    expect(brojStranice({ stranica: '3' })).toBe(3);
    expect(brojStranice({ stranica: '-1' })).toBe(1);
    expect(brojStranice({})).toBe(1);
  });
  it('odgovara po državi, županiji i gradu bez dijakritike', () => {
    const o = oglas({ grad: 'Šibenik', zupanija: 'Šibensko-kninska' });
    expect(odgovara(o, { grad: 'sibenik' }, sada)).toBe(true);
    expect(odgovara(o, { q: 'sibensko' }, sada)).toBe(true);
    expect(odgovara(o, { drzava: 'BA' }, sada)).toBe(false);
    expect(odgovara(o, { zupanija: 'Šibensko-kninska' }, sada)).toBe(true);
    expect(odgovara(oglas({ istjece: '2026-11-01T00:00:00Z' }), {}, sada)).toBe(false);
  });
  it('sortiranje po cijeni stavlja "dogovor" na kraj', () => {
    const l = [oglas({ id: 'a', cijena: 5 }), oglas({ id: 'b', cijena: null }), oglas({ id: 'c', cijena: 50 })];
    expect(sortiraj(l, 'cijena_padajuce').map((o) => o.id)).toEqual(['c', 'a', 'b']);
  });
});

describe('objava', () => {
  const nacrt = {
    naslov: 'Kovanica 5 kuna 1993', kategorija: 'kovanice-i-novcanice', opis: 'Prvo izdanje, lijepo očuvana.', cijena: 12.5,
    drzava: 'HR', zupanija: 'Splitsko-dalmatinska', grad: 'Split', stanje: 'Dobro', polja: { godina: '1993', nepoznato: 'x' }, prikazi_telefon: false,
  };
  it('ispravan nacrt prolazi, nepoznata polja se brišu', () => {
    expect(provjeriOglas(nacrt, 1)).toEqual({});
    expect(ocistiNacrt(nacrt).polja).toEqual({ godina: '1993' });
  });
  it('izvan Hrvatske županija nije obavezna', () => {
    expect(provjeriOglas({ ...nacrt, drzava: 'SI', zupanija: null, grad: 'Ljubljana' }, 1)).toEqual({});
    expect(ocistiNacrt({ ...nacrt, drzava: 'SI', zupanija: '  ', grad: ' Ljubljana ' })).toMatchObject({ zupanija: null, grad: 'Ljubljana' });
  });
  it('greške po polju', () => {
    const g = provjeriOglas({ ...nacrt, naslov: 'a', stanje: 'Super', zupanija: 'X', cijena: -1 }, 0);
    expect(Object.keys(g).sort()).toEqual(['cijena', 'naslov', 'slike', 'stanje', 'zupanija']);
  });
});

describe('SEO', () => {
  it('adresa oglasa ima čist slug', () => {
    expect(putOglasa(oglas())).toBe('/oglas/11111111-1111-1111-1111-111111111111/charizard-base-set-4-102');
    expect(slug('Pokémon Šibenik – 1. izdanje!')).toBe('pokemon-sibenik-1-izdanje');
    expect(normaliziraj('ŠĐČĆŽ')).toBe('sdccz');
  });
  it('JSON-LD: cijena, dostupnost i adresa', () => {
    const j = jsonLdOglas(oglas()) as { offers: Record<string, unknown> };
    expect(j.offers).toMatchObject({ price: '250.00', priceCurrency: 'EUR', availability: 'https://schema.org/InStock' });
    expect(JSON.stringify(j)).toContain('"addressRegion":"Grad Zagreb"');
    expect(JSON.stringify(j)).toContain('"addressCountry":"HR"');
  });
  it('JSON-LD: "dogovor" nema cijenu, a prodano nije na zalihi', () => {
    const j = jsonLdOglas(oglas({ cijena: null, status: 'prodano' })) as { offers: Record<string, unknown> };
    expect(j.offers.price).toBeUndefined();
    expect(j.offers.availability).toBe('https://schema.org/SoldOut');
  });
  it('JSON u skripti ne može zatvoriti oznaku', () => {
    expect(jsonUScript({ a: '</script><b>' })).not.toContain('</script>');
  });
  it('opis oglasa je najviše 158 znakova i sadrži lokaciju', () => {
    const d = opisOglasa(oglas({ opis: 'x'.repeat(500) }));
    expect(d.length).toBeLessThanOrEqual(158);
    expect(d).toContain('Zagreb');
    expect(cijenaTekst(null)).toBe('Dogovor');
  });
});
