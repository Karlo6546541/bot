import 'fake-indexeddb/auto';
import { beforeEach, describe, expect, it } from 'vitest';
import { _resetiraj } from '../src/data/idb';
import { LokalniBackend } from '../src/data/lokalno';
import type { NacrtOglasa, SlikaZaSpremanje } from '../src/data/types';

const mem = new Map<string, string>();
globalThis.localStorage = {
  getItem: (k: string) => mem.get(k) ?? null,
  setItem: (k: string, v: string) => void mem.set(k, v),
  removeItem: (k: string) => void mem.delete(k),
} as Storage;

const slika: SlikaZaSpremanje = { vrsta: 'postojeca', url: 'data:velika', mala: 'data:mala' };
const nacrt: NacrtOglasa = {
  naslov: 'Charizard Base Set 4/102',
  kategorija: 'kartice',
  opis: 'Holo, lagano izlizani rubovi.',
  cijena: 250,
  zupanija: 'Grad Zagreb',
  grad: 'Zagreb',
  stanje: 'Dobro',
  polja: { igra: 'Pokémon', set: 'Base Set' },
  prikazi_telefon: true,
};

let sat = Date.parse('2026-11-20T12:00:00Z');
const dan = 86400000;

beforeEach(async () => {
  await _resetiraj();
  mem.clear();
  sat = Date.parse('2026-11-20T12:00:00Z');
});

describe('lokalni oglasnik', () => {
  it('registracija, objava, pretraga, poruka, kontakti', async () => {
    const b = new LokalniBackend(() => sat);
    await b.registracija('prodavac@test.hr', 'lozinka123', 'Ana');
    const ana = (await b.trenutni())!;
    expect(ana.admin).toBe(true); // prvi korisnik u demo načinu
    await b.spremiProfil({ ime: 'Ana', grad: 'Zagreb', telefon: '091 123 4567' });
    const o = await b.spremiOglas(nacrt, [slika]);
    expect(o.vrsta_prodaje).toBe('fiksna_cijena');
    expect(Date.parse(o.istjece) - sat).toBe(30 * dan);

    await b.odjava();
    await b.registracija('kupac@test.hr', 'lozinka123', 'Marko');
    const marko = (await b.trenutni())!;
    expect(marko.admin).toBe(false);
    const r = await b.trazi({ q: 'charizard', polja: { igra: 'Pokemon' } }, 0);
    expect(r.ukupno).toBe(1);
    const razgovor = await b.zapocniRazgovor(o.id, 'Je li još dostupno?');
    expect(await b.telefon(o.id)).toBe('091 123 4567');
    await b.postaviFavorit(o.id, true);
    expect((await b.favoriti()).map((x) => x.id)).toEqual([o.id]);

    await b.odjava();
    await b.prijava('prodavac@test.hr', 'lozinka123');
    const s = await b.razgovori();
    expect(s).toHaveLength(1);
    expect(s[0].neprocitano).toBe(true);
    await b.oznaciProcitano(razgovor);
    expect((await b.razgovori())[0].neprocitano).toBe(false);
    await b.posalji(razgovor, 'Da, dostupno je.');
    const k = await b.kontakti(o.id);
    expect(k.map((x) => x.vrsta).sort()).toEqual(['poruka', 'telefon']);
    await expect(b.prijava('prodavac@test.hr', 'kriva')).rejects.toThrow('Pogrešan');
  });

  it('istek, produljenje, prodano s cijenom, meko brisanje', async () => {
    const b = new LokalniBackend(() => sat);
    await b.registracija('a@test.hr', 'lozinka123', 'Ana');
    const o = await b.spremiOglas(nacrt, [slika]);
    sat += 31 * dan;
    expect((await b.trazi({}, 0)).ukupno).toBe(0);
    await b.produlji(o.id);
    expect((await b.trazi({}, 0)).ukupno).toBe(1);
    await b.oznaciProdano(o.id, 230);
    const p = (await b.oglas(o.id))!;
    expect(p.status).toBe('prodano');
    expect(p.prodano_cijena).toBe(230);
    expect(p.prodano_datum).toBeTruthy();
    expect((await b.trazi({}, 0)).ukupno).toBe(0);
    await b.obrisi(o.id);
    expect(await b.mojiOglasi()).toEqual([]);
  });

  it('moderacija: prijava, uklanjanje, blokada', async () => {
    const b = new LokalniBackend(() => sat);
    await b.registracija('admin@test.hr', 'lozinka123', 'Admin');
    await b.odjava();
    await b.registracija('varalica@test.hr', 'lozinka123', 'Varalica');
    const v = (await b.trenutni())!;
    const o = await b.spremiOglas(nacrt, [slika]);
    await b.odjava();
    await b.registracija('kupac@test.hr', 'lozinka123', 'Kupac');
    await b.prijaviOglas(o.id, 'krivotvorina', 'Lažna kartica');
    await expect(b.prijaviOglas(o.id, 'prevara', '')).rejects.toThrow('Već');
    await expect(b.prijave()).rejects.toThrow('administratore');
    await b.odjava();
    await b.prijava('admin@test.hr', 'lozinka123');
    const p = await b.prijave();
    expect(p[0].oglas?.naslov).toBe(nacrt.naslov);
    await b.ukloniOglas(o.id, 'Krivotvorina');
    await b.blokiraj(v.id, true);
    await b.odjava();
    expect(await b.oglas(o.id)).toBeNull();
    await b.prijava('varalica@test.hr', 'lozinka123');
    expect((await b.oglas(o.id))?.status).toBe('uklonjen');
    await expect(b.spremiOglas(nacrt, [slika])).rejects.toThrow('blokiran');
  });

  it('objava bez fotografije nije moguća', async () => {
    const b = new LokalniBackend(() => sat);
    await b.registracija('a@test.hr', 'lozinka123', 'Ana');
    await expect(b.spremiOglas(nacrt, [])).rejects.toThrow('fotografiju');
  });
});
