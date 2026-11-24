// Migracije oglasnika na pravom Postgresu (PGlite): lokacija (država, županija,
// grad), pretraga bez dijakritike i pravila pristupa (RLS).
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { readFileSync, readdirSync } from 'node:fs';
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
  -- tablice Flutter aplikacije (sinkronizacija oglasa)
  create table public.loop_devices (id text primary key, data jsonb, updated_at timestamptz default now());
  create table public.loop_auctions (id text primary key, data jsonb, updated_at timestamptz default now());
  create table public.loop_usernames (username text primary key, user_id uuid, created_at timestamptz default now());
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
  for (const f of readdirSync('supabase/migrations').sort()) {
    await db.exec(readFileSync(`supabase/migrations/${f}`, 'utf8'));
  }
  await db.exec(`grant select, insert, update, delete on all tables in schema public to anon, authenticated;`);
  await kao(ANA);
  await upit(`insert into oglasnik_profili (id, ime) values ($1, 'Ana')`, [ANA]);
});

const OGLAS = `insert into oglasnik_oglasi (korisnik_id, naslov, kategorija, opis, cijena, drzava, zupanija, grad, stanje, polja, slike, slike_male)
  values ($1, $2, 'pokemon-i-ostali-tcg', 'Holo kartica, odlično očuvana.', 250, $3, $4, $5, 'Dobro', '{"igra":"Pokémon"}', array['a.webp'], array['a-m.webp']) returning *`;

describe('lokacija oglasa', () => {
  it('zadana država je Hrvatska; županija je neobavezna izvan nje', async () => {
    await kao(ANA);
    const [hr] = await upit<{ drzava: string }>(
      `insert into oglasnik_oglasi (korisnik_id, naslov, kategorija, opis, zupanija, grad, stanje, slike, slike_male)
       values ($1, 'Kovanica', 'kovanice', 'Stara kovanica iz zbirke.', 'Grad Zagreb', 'Zagreb', 'Dobro', array['a'], array['a']) returning drzava`,
      [ANA],
    );
    expect(hr.drzava).toBe('HR');
    const [ba] = await upit<{ drzava: string; zupanija: string | null }>(OGLAS, [ANA, 'Strip iz Sarajeva', 'BA', null, 'Sarajevo']);
    expect(ba).toMatchObject({ drzava: 'BA', zupanija: null });
  });

  it('neispravan kod države i prekratka županija se odbijaju', async () => {
    await kao(ANA);
    await expect(upit(OGLAS, [ANA, 'X', 'hr', 'Grad Zagreb', 'Zagreb'])).rejects.toThrow(/check constraint/);
    await expect(upit(OGLAS, [ANA, 'X', 'Hrvatska', 'Grad Zagreb', 'Zagreb'])).rejects.toThrow(/check constraint/);
    await expect(upit(OGLAS, [ANA, 'X', 'HR', 'Z', 'Zagreb'])).rejects.toThrow(/check constraint/);
  });

  it('pretraga nalazi po gradu i županiji bez dijakritike', async () => {
    await kao(ANA);
    await upit(OGLAS, [ANA, 'Charizard Base Set', 'HR', 'Splitsko-dalmatinska', 'Šibenik']);
    await kao(null);
    const poGradu = await upit(`select naslov from oglasnik_oglasi where pretraga like '%sibenik%'`);
    expect(poGradu.map((r) => r.naslov)).toEqual(['Charizard Base Set']);
    const poZupaniji = await upit(`select naslov from oglasnik_oglasi where pretraga like '%dalmatinska%'`);
    expect(poZupaniji).toHaveLength(1);
  });

  it('grad se filtrira bez dijakritike (grad_n)', async () => {
    await kao(null);
    const r = await upit(`select grad from oglasnik_oglasi where grad_n like '%sibenik%'`);
    expect(r).toEqual([{ grad: 'Šibenik' }]);
  });

  it('filter po državi i županiji koristi indeks i vraća samo traženo', async () => {
    await kao(null);
    const ba = await upit(`select grad from oglasnik_oglasi where drzava = 'BA'`);
    expect(ba).toEqual([{ grad: 'Sarajevo' }]);
    const hr = await upit(`select count(*)::int as n from oglasnik_oglasi where drzava = 'HR' and zupanija = 'Grad Zagreb'`);
    expect(hr[0].n).toBe(1);
  });
});

describe('pravila pristupa (nepromijenjena)', () => {
  it('korisnik ne može sebi dati admina, tuđi oglas ne može mijenjati', async () => {
    await kao(MARKO);
    await upit(`insert into oglasnik_profili (id, ime, admin) values ($1, 'Marko', true)`, [MARKO]);
    expect((await upit<{ admin: boolean }>(`select admin from oglasnik_profili where id = $1`, [MARKO]))[0].admin).toBe(false);
    await upit(`update oglasnik_oglasi set naslov = 'Hakirano'`);
    await kao(null);
    expect(await upit(`select 1 from oglasnik_oglasi where naslov = 'Hakirano'`)).toEqual([]);
  });

  it('prijava oglasa vidljiva je samo adminu', async () => {
    await kao(null);
    const [o] = await upit<{ id: string }>(`select id from oglasnik_oglasi limit 1`);
    await kao(MARKO);
    await upit(`insert into oglasnik_prijave (oglas_id, prijavitelj_id, razlog) values ($1, $2, 'prevara')`, [o.id, MARKO]);
    expect(await upit(`select * from oglasnik_prijave`)).toEqual([]);
    await kao(null);
    await db.exec('reset role'); // kao SQL editor: bez prijavljenog korisnika
    await upit(`insert into oglasnik_profili (id, ime, admin) values ($1, 'Admin', true) on conflict (id) do update set admin = true`, [ADMIN]);
    await kao(ADMIN);
    expect(await upit(`select * from oglasnik_prijave`)).toHaveLength(1);
  });
});

describe('sinkronizacija s Flutter aplikacijom', () => {
  it('oglas objavljen na webu pojavi se u aplikaciji (loop_devices)', async () => {
    await kao(ANA);
    const [o] = await upit<{ id: string }>(OGLAS, [ANA, 'Sync web kartica', 'HR', 'Istarska', 'Pula']);
    await db.exec('reset role');
    const [d] = await upit<{ id: string; data: Record<string, unknown> }>(`select id, data from loop_devices where id = $1`, [`web-${o.id}`]);
    expect(d.data).toMatchObject({ name: 'Sync web kartica', category: 'tcg', condition: 'good', ownerId: ANA });
    expect(Number(d.data.listPrice)).toBe(250);
    const [veza] = await upit<{ izvor_id: string }>(`select izvor_id from oglasnik_oglasi where id = $1`, [o.id]);
    expect(veza.izvor_id).toBe(`web-${o.id}`);
  });

  it('izmjena i prodaja na webu prenose se u aplikaciju', async () => {
    await kao(ANA);
    const [o] = await upit<{ id: string }>(`select id from oglasnik_oglasi where naslov = 'Sync web kartica'`);
    await upit(`update oglasnik_oglasi set cijena = 199, status = 'prodano' where id = $1`, [o.id]);
    await db.exec('reset role');
    const [d] = await upit<{ data: Record<string, unknown> }>(`select data from loop_devices where id = $1`, [`web-${o.id}`]);
    expect(Number(d.data.price)).toBe(199);
    expect(d.data.soldAt).toBeTruthy();
  });

  it('oglas iz aplikacije pojavi se na webu, a brisanje u aplikaciji ga skida', async () => {
    await db.exec('reset role');
    await upit(`insert into loop_devices (id, data) values ('app-1', $1)`, [JSON.stringify({
      id: 'app-1', name: 'Markica iz aplikacije', price: 30, listPrice: 30, ownerId: MARKO, category: 'stamps', condition: 'excellent',
      listedAt: new Date().toISOString(), createdAt: new Date().toISOString(), imagePaths: ['https://example.com/m.jpg'], description: 'Opis iz aplikacije, dovoljno dug.',
    })]);
    const [w] = await upit<{ kategorija: string; stanje: string; cijena: string; status: string }>(`select kategorija, stanje, cijena, status from oglasnik_oglasi where izvor_id = 'app-1'`);
    expect(w).toMatchObject({ kategorija: 'markice', stanje: 'Odlično', status: 'aktivan' });
    expect(Number(w.cijena)).toBe(30);
    await upit(`delete from loop_devices where id = 'app-1'`);
    const [w2] = await upit<{ status: string }>(`select status from oglasnik_oglasi where izvor_id = 'app-1'`);
    expect(w2.status).toBe('obrisan');
    // nema petlje: brisanje nije vratilo zapis u aplikaciju
    expect(await upit(`select 1 from loop_devices where id = 'app-1'`)).toHaveLength(0);
  });
});
