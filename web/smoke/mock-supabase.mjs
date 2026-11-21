// Lažni Supabase REST (PostgREST) nad PGlite: pokreće prave migracije i RLS kao
// anon korisnik, pa SSR stranice mogu čitati oglase bez prave baze.
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { createServer } from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';

const PORT = Number(process.env.MOCK_PORT ?? 54321);
const db = new PGlite({ extensions: { pg_trgm } });
await db.exec(`
  create role anon; create role authenticated;
  create schema auth; create schema extensions; create schema storage;
  create table auth.users (id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
  create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
  alter table storage.objects enable row level security;
  grant usage on schema auth, storage, extensions, public to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;
`);
for (const f of readdirSync('supabase/migrations').sort()) await db.exec(readFileSync(`supabase/migrations/${f}`, 'utf8'));
await db.exec('grant select, insert, update, delete on all tables in schema public to anon, authenticated;');

// ---- Probni podaci: više država, županija, gradova i kategorija ----
const U = ['00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2'];
await db.exec(`insert into auth.users values ('${U[0]}','ana@test.hr'),('${U[1]}','luka@test.hr')`);
await db.exec(`insert into oglasnik_profili (id, ime, grad) values ('${U[0]}','Ana Kolekcionar','Zagreb'),('${U[1]}','Luka','Split')`);
const KAT = [
  ['kartice', 'Charizard Base Set', { igra: 'Pokémon', set: 'Base Set', jezik: 'Engleski' }],
  ['kovanice-i-novcanice', 'Kovanica 5 kuna 1993', { drzava: 'Hrvatska', godina: '1993' }],
  ['stripovi-i-manga', 'Alan Ford broj 1', { izdavac: 'Bonelli', jezik: 'Hrvatski' }],
  ['gramofonske-ploce', 'Pink Floyd – The Wall', { izvodjac: 'Pink Floyd', format: 'LP', godina: '1979' }],
  ['marke', 'Marke Jugoslavija 1960-ih', { drzava: 'Jugoslavija' }],
  ['figurice', 'Smurfovi figurice lot', { proizvodjac: 'Schleich' }],
];
const MJESTA = [
  ['HR', 'Grad Zagreb', 'Zagreb'], ['HR', 'Splitsko-dalmatinska', 'Split'], ['HR', 'Šibensko-kninska', 'Šibenik'],
  ['HR', 'Istarska', 'Pula'], ['BA', null, 'Sarajevo'], ['SI', null, 'Ljubljana'], ['HR', 'Grad Zagreb', 'Zagreb'],
];
let i = 0;
for (const [kat, naslov, polja] of KAT) {
  for (let k = 0; k < 6; k++, i++) {
    const [dr, zup, grad] = MJESTA[i % MJESTA.length];
    const cijena = k === 5 ? null : 5 + ((i * 13) % 200);
    await db.query(
      `insert into oglasnik_oglasi (korisnik_id,naslov,kategorija,opis,cijena,drzava,zupanija,grad,stanje,polja,slike,slike_male)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [U[i % 2], `${naslov} #${k + 1}`, kat, `Opis predmeta ${naslov}. Lijepo očuvano, može osobno preuzimanje u mjestu ${grad}.`, cijena, dr, zup, grad,
        ['Novo', 'Kao novo', 'Dobro', 'Oštećeno'][i % 4], JSON.stringify(polja),
        [`http://127.0.0.1:${PORT}/slika/${i}.svg`], [`http://127.0.0.1:${PORT}/slika/${i}.svg`]],
    );
  }
}
// različita vremena objave
await db.exec(`update oglasnik_oglasi set objavljeno = now() - (random() * interval '10 days')`);
// jedan prodani i jedan istekli oglas (ne smiju u popis)
await db.exec(`update oglasnik_oglasi set status='prodano' where naslov = 'Alan Ford broj 1 #1'`);
await db.exec(`update oglasnik_oglasi set istjece = now() - interval '1 day' where naslov = 'Alan Ford broj 1 #2'`);

// ---- PostgREST podskup ----
const IDENT = /^[a-z_]+(->>[a-z_]+)?$/;
const kol = (k) => {
  if (!IDENT.test(k)) throw new Error(`neispravan stupac ${k}`);
  return k.includes('->>') ? `(${k.split('->>')[0]}->>'${k.split('->>')[1]}')` : k;
};
const OPS = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=', like: 'like', ilike: 'ilike' };

async function upit(url, head) {
  const tablica = url.pathname.replace('/rest/v1/', '');
  if (!/^oglasnik_[a-z_]+$/.test(tablica)) return { status: 404, body: { message: 'nema tablice' } };
  const cond = [];
  const p = [];
  let order = '';
  let limit = '';
  let offset = '';
  let select = '*';
  for (const [k, v] of url.searchParams) {
    if (k === 'select') select = v;
    else if (k === 'order') {
      order = v.split(',').map((o) => {
        const [c, ...r] = o.split('.');
        return `${kol(c)} ${r.includes('desc') ? 'desc' : 'asc'}${r.includes('nullslast') ? ' nulls last' : r.includes('nullsfirst') ? ' nulls first' : ''}`;
      }).join(', ');
    } else if (k === 'limit') limit = ` limit ${Number(v) | 0}`;
    else if (k === 'offset') offset = ` offset ${Number(v) | 0}`;
    else {
      const [op, ...rest] = v.split('.');
      const val = rest.join('.');
      if (op === 'in') {
        const arr = val.replace(/^\(|\)$/g, '').split(',');
        cond.push(`${kol(k)}::text = any($${p.push(arr)})`);
      } else if (['gt', 'gte', 'lt', 'lte'].includes(op)) cond.push(`${kol(k)} ${OPS[op]} $${p.push(val)}`);
      else if (OPS[op]) cond.push(`${kol(k)}::text ${OPS[op]} $${p.push(val)}`);
      else throw new Error(`operator ${op}`);
    }
  }
  const stupci = select === '*' ? '*' : select.split(',').map((s) => {
    if (!/^[a-z_]+$/.test(s)) throw new Error('select');
    return s;
  }).join(',');
  const where = cond.length ? ` where ${cond.join(' and ')}` : '';
  await db.exec('reset role');
  await db.exec('set role anon');
  const n = (await db.query(`select count(*)::int as n from ${tablica}${where}`, p)).rows[0].n;
  const redovi = head ? [] : (await db.query(`select coalesce(jsonb_agg(t), '[]'::jsonb) as j from (select ${stupci} from ${tablica}${where}${order ? ` order by ${order}` : ''}${limit}${offset}) t`, p)).rows[0].j;
  const od = Number(url.searchParams.get('offset') ?? 0);
  const len = Array.isArray(redovi) ? redovi.length : 0;
  return { status: 200, body: redovi, range: n === 0 ? '*/0' : `${od}-${od + Math.max(0, len - 1)}/${n}` };
}

const boje = ['#1f6f7a', '#b36b00', '#5b3d99', '#2e7d32', '#aa3333', '#333366'];
createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-expose-headers': 'content-range' };
  if (req.method === 'OPTIONS') return res.writeHead(204, cors).end();
  if (url.pathname.startsWith('/slika/')) {
    const n = parseInt(url.pathname.slice(7)) || 0;
    res.writeHead(200, { 'content-type': 'image/svg+xml', ...cors });
    return res.end(`<svg xmlns="http://www.w3.org/2000/svg" width="480" height="480"><rect width="480" height="480" fill="${boje[n % boje.length]}"/><text x="240" y="260" font-size="120" text-anchor="middle" fill="#fff" font-family="Arial">${n + 1}</text></svg>`);
  }
  if (url.pathname.startsWith('/rest/v1/')) {
    try {
      const r = await upit(url, req.method === 'HEAD');
      res.writeHead(r.status, { 'content-type': 'application/json', ...(r.range ? { 'content-range': r.range } : {}), ...cors });
      return res.end(req.method === 'HEAD' ? '' : JSON.stringify(r.body));
    } catch (e) {
      res.writeHead(400, { 'content-type': 'application/json', ...cors });
      return res.end(JSON.stringify({ message: String(e.message) }));
    }
  }
  if (url.pathname.startsWith('/auth/v1/')) {
    res.writeHead(200, { 'content-type': 'application/json', ...cors });
    return res.end(JSON.stringify({ user: null }));
  }
  res.writeHead(404, cors).end();
}).listen(PORT, '127.0.0.1', () => console.log(`mock supabase na ${PORT}`));
