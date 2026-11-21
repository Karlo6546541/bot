// SQL migracija oglasnika na pravom Postgresu (PGlite): RLS, okidači i
// funkcije, uz glumljene Supabase sheme auth i storage.
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { readFileSync } from 'node:fs';
import { beforeAll, describe, expect, it } from 'vitest';

const db = new PGlite({ extensions: { pg_trgm } });
const ANA = '00000000-0000-0000-0000-00000000000a';
const MARKO = '00000000-0000-0000-0000-00000000000b';
const ADMIN = '00000000-0000-0000-0000-00000000000c';

async function kao(id: string | null) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id ?? '']);
  await db.exec(id ? 'set role authenticated' : 'set role anon');
}
const upit = async <T = Record<string, unknown>>(sql: string, p: unknown[] = []) =>
  (await db.query<T>(sql, p)).rows;

beforeAll(async () => {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema extensions; create schema storage;
    create table auth.users (id uuid primary key, email text);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create table storage.buckets (id text primary key, name text, public boolean,
      file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
    create function storage.foldername(name text) returns text[] language sql immutable as
      $$ select string_to_array(name, '/') $$;
    alter table storage.objects enable row level security;
    grant usage on schema auth, storage, extensions, public to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;
    insert into auth.users values ('${ANA}', 'ana@test.hr'), ('${MARKO}', 'marko@test.hr'), ('${ADMIN}', 'admin@test.hr');
  `);
  await db.exec(readFileSync('supabase/migrations/20261120120000_oglasnik.sql', 'utf8'));
  await db.exec(`
    grant select, insert, update, delete on all tables in schema public to anon, authenticated;
    grant select, insert, delete on storage.objects to authenticated;
  `);
  // Admin se postavlja ručno (kao u produkciji).
  await kao(ADMIN);
  await upit(`insert into oglasnik_profili (id, ime) values ($1, 'Admin')`, [ADMIN]);
  await kao(null);
  await db.exec('reset role'); // kao SQL editor: bez prijavljenog korisnika
  await upit(`update oglasnik_profili set admin = true where id = $1`, [ADMIN]);
});

const OGLAS = `insert into oglasnik_oglasi (korisnik_id, naslov, kategorija, opis, cijena, zupanija, grad, stanje, polja, slike, slike_male, prikazi_telefon)
  values ($1, 'Charizard Base Set', 'kartice', 'Holo kartica, odlično očuvana.', 250, 'Grad Zagreb', 'Zagreb', 'Dobro',
  '{"igra":"Pokémon"}', array['a.webp'], array['a-m.webp'], true) returning *`;

describe('baza oglasnika', () => {
  let oglasId = '';

  it('profil: korisnik ne može sebi dati admina', async () => {
    await kao(ANA);
    const [p] = await upit<{ admin: boolean }>(
      `insert into oglasnik_profili (id, ime, admin) values ($1, 'Ana', true) returning admin`,
      [ANA],
    );
    expect(p.admin).toBe(false);
    await upit(`update oglasnik_profili set admin = true, blokiran = false where id = $1`, [ANA]);
    expect((await upit<{ admin: boolean }>(`select admin from oglasnik_profili where id = $1`, [ANA]))[0].admin).toBe(false);
    await upit(`insert into oglasnik_privatno (id, telefon) values ($1, '091 111 2222')`, [ANA]);
    await kao(MARKO);
    await upit(`insert into oglasnik_profili (id, ime) values ($1, 'Marko')`, [MARKO]);
    expect(await upit(`select * from oglasnik_privatno`)).toEqual([]);
  });

  it('oglas: objava, fiksna cijena, istek 30 dana, pretraga bez dijakritike', async () => {
    await kao(ANA);
    const [o] = await upit<{ id: string; vrsta_prodaje: string; status: string; d: number }>(OGLAS, [ANA]);
    oglasId = o.id;
    expect(o.vrsta_prodaje).toBe('fiksna_cijena');
    const [x] = await upit<{ dana: number }>(
      `select round(extract(epoch from istjece - objavljeno) / 86400) as dana from oglasnik_oglasi where id = $1`,
      [oglasId],
    );
    expect(Number(x.dana)).toBe(30);
    await kao(null);
    const r = await upit(`select id from oglasnik_oglasi where pretraga like '%ocuvana%' and pretraga like '%pokemon%'`);
    expect(r).toHaveLength(1);
    // Tuđi korisnik ne može objaviti u ime drugoga ni bez fotografije.
    await kao(MARKO);
    await expect(upit(OGLAS, [ANA])).rejects.toThrow(/row-level security/);
    await expect(
      upit(OGLAS.replace("array['a.webp'], array['a-m.webp']", "array[]::text[], array[]::text[]"), [MARKO]),
    ).rejects.toThrow(/check constraint/);
    // Ne može mijenjati tuđi oglas (0 redaka).
    await upit(`update oglasnik_oglasi set cijena = 1 where id = $1`, [oglasId]);
    await kao(null);
    expect((await upit<{ cijena: string }>(`select cijena from oglasnik_oglasi where id = $1`, [oglasId]))[0].cijena).toBe('250.00');
  });

  it('vlasnik: produljenje najviše 30 dana, ne može sam ukloniti oglas', async () => {
    await kao(ANA);
    await upit(`update oglasnik_oglasi set istjece = now() + interval '1 year' where id = $1`, [oglasId]);
    const [x] = await upit<{ dana: number }>(
      `select round(extract(epoch from istjece - now()) / 86400) as dana from oglasnik_oglasi where id = $1`,
      [oglasId],
    );
    expect(Number(x.dana)).toBe(30);
    await expect(upit(`update oglasnik_oglasi set status = 'uklonjen' where id = $1`, [oglasId])).rejects.toThrow(
      /administrator/,
    );
  });

  it('poruke: razgovor bilježi kontakt, telefon samo prijavljenima', async () => {
    await kao(MARKO);
    const [r] = await upit<{ id: string; prodavatelj_id: string }>(
      `insert into oglasnik_razgovori (oglas_id, kupac_id, prodavatelj_id) values ($1, $2, $2) returning *`,
      [oglasId, MARKO],
    );
    expect(r.prodavatelj_id).toBe(ANA); // uzima se iz oglasa, ne od klijenta
    await upit(`insert into oglasnik_poruke (razgovor_id, posiljatelj_id, tekst) values ($1, $2, 'Je li dostupno?')`, [r.id, MARKO]);
    expect((await upit<{ t: string }>(`select oglasnik_telefon($1) as t`, [oglasId]))[0].t).toBe('091 111 2222');
    await kao(ANA);
    const [z] = await upit<{ kupac_procitao: string | null; prodavatelj_procitao: string | null }>(
      `select * from oglasnik_razgovori where id = $1`,
      [r.id],
    );
    expect(z.kupac_procitao).not.toBeNull();
    expect(z.prodavatelj_procitao).toBeNull();
    await upit(`select oglasnik_procitano($1)`, [r.id]);
    const k = await upit<{ vrsta: string }>(`select vrsta from oglasnik_kontakti where oglas_id = $1 order by vrsta`, [oglasId]);
    expect(k.map((x) => x.vrsta)).toEqual(['poruka', 'telefon']);
    // Treća osoba ne vidi razgovor ni kontakte.
    await kao(ADMIN);
    expect(await upit(`select * from oglasnik_poruke`)).toEqual([]);
    await kao(null);
    await expect(upit(`select oglasnik_telefon($1)`, [oglasId])).rejects.toThrow(/permission denied/);
  });

  it('prodano: datum i konačna cijena se spremaju', async () => {
    await kao(ANA);
    await upit(`update oglasnik_oglasi set status = 'prodano', prodano_cijena = 230 where id = $1`, [oglasId]);
    const [o] = await upit<{ prodano_datum: string | null; prodano_cijena: string }>(
      `select prodano_datum, prodano_cijena from oglasnik_oglasi where id = $1`,
      [oglasId],
    );
    expect(o.prodano_datum).not.toBeNull();
    expect(o.prodano_cijena).toBe('230.00');
    await upit(`update oglasnik_oglasi set status = 'aktivan' where id = $1`, [oglasId]);
  });

  it('moderacija: prijava, uklanjanje, blokada', async () => {
    await kao(MARKO);
    await upit(`insert into oglasnik_prijave (oglas_id, prijavitelj_id, razlog) values ($1, $2, 'krivotvorina')`, [oglasId, MARKO]);
    expect(await upit(`select * from oglasnik_prijave`)).toEqual([]); // samo admin čita
    await kao(ADMIN);
    expect(await upit(`select * from oglasnik_prijave`)).toHaveLength(1);
    await upit(`update oglasnik_oglasi set status = 'uklonjen', uklonjeno_razlog = 'Krivotvorina' where id = $1`, [oglasId]);
    await upit(`update oglasnik_profili set blokiran = true where id = $1`, [ANA]);
    await kao(null);
    expect(await upit(`select id from oglasnik_oglasi where id = $1`, [oglasId])).toEqual([]);
    await kao(ANA);
    expect(await upit(`select status from oglasnik_oglasi where id = $1`, [oglasId])).toEqual([{ status: 'uklonjen' }]);
    await expect(upit(`update oglasnik_oglasi set status = 'aktivan' where id = $1`, [oglasId])).resolves.toBeDefined();
    expect((await upit(`select status from oglasnik_oglasi where id = $1`, [oglasId]))[0]).toEqual({ status: 'uklonjen' });
    await expect(upit(OGLAS, [ANA])).rejects.toThrow(/row-level security/);
  });

  it('slike: upload samo u svoju mapu', async () => {
    await kao(MARKO);
    await upit(`insert into storage.objects (bucket_id, name) values ('oglasnik-slike', $1)`, [`${MARKO}/x/1.webp`]);
    await expect(
      upit(`insert into storage.objects (bucket_id, name) values ('oglasnik-slike', $1)`, [`${ANA}/x/1.webp`]),
    ).rejects.toThrow(/row-level security/);
  });
});
