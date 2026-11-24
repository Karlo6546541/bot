// Popis hrvatskih tekstova koji se prevode (t('...'), prevedi(x, '...')) i podataka koji idu kroz t().
// Pokretanje: node scripts/kljucevi_prijevoda.mjs [--nedostaju]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const datoteke = [];
const obidi = (d) => readdirSync(d).forEach((f) => { const p = join(d, f); statSync(p).isDirectory() ? obidi(p) : /\.tsx?$/.test(f) && datoteke.push(p); });
['app', 'components', 'lib'].forEach(obidi);
const k = new Set();
const lit = String.raw`'((?:[^'\\]|\\.)*)'`;
const re = [new RegExp(String.raw`\bt\(\s*` + lit, 'g'), new RegExp(String.raw`prevedi\(\s*[\w.]+\s*,\s*` + lit, 'g'), new RegExp(String.raw`\bt\(\s*\w+(?:\.\w+)*\s*===\s*1\s*\?\s*` + lit + String.raw`\s*:\s*` + lit, 'g')];
for (const f of datoteke) {
  if (f.endsWith('prijevodi-en.ts') || f.endsWith('i18n.ts')) continue;
  const s = readFileSync(f, 'utf8');
  for (const r of re) for (const m of s.matchAll(r)) { k.add(m[1].replace(/\\'/g, "'")); if (m[2]) k.add(m[2].replace(/\\'/g, "'")); }
  // provjere obrazaca i poruke grešaka su hrvatski tekstovi koji se prikazuju kroz t()
  if (/lib\/(provjera|korisnik|lokacije)\.ts$/.test(f)) for (const m of s.matchAll(/(?:=|return)\s*'([A-ZČĆŠŽĐ][^']*)'/g)) k.add(m[1]);
}
// podaci koji se prikazuju kroz t()
const kat = readFileSync('lib/kategorije.ts', 'utf8');
for (const m of kat.matchAll(/naziv: "([^"]+)", tip/g)) k.add(m[1]);
for (const m of kat.matchAll(/opcije: \[([^\]]+)\]/g)) for (const o of m[1].matchAll(/"((?:[^"\\]|\\.)+)"/g)) k.add(JSON.parse(`"${o[1]}"`));
for (const m of kat.matchAll(/placeholder: "([^"]+)"/g)) k.add(m[1]);
for (const m of kat.matchAll(/STANJA = \[([^\]]+)\]/g)) for (const o of m[1].matchAll(/'([^']+)'/g)) k.add(o[1]);
for (const m of kat.matchAll(/naziv: '([^']+)' \}/g)) k.add(m[1]);
['aktivan', 'prodano', 'uklonjen', 'obrisan', 'Početna', 'Kategorije', 'Prodaj', 'Poruke', 'Profil', 'Aktivni', 'Istekli', 'Prodani', 'Uklonjeni', 'Prevara', 'Krivotvorina', 'Neprimjeren sadržaj', 'Ostalo', 'Najviše 8 fotografija.'].forEach((x) => k.add(x));

const svi = [...k].filter((x) => /\p{L}{2}/u.test(x) && x !== 'HR').sort();
if (process.argv.includes('--nedostaju')) {
  const src = readFileSync('lib/prijevodi-en.ts', 'utf8');
  const nema = svi.filter((x) => !src.includes(JSON.stringify(x) + ':') && !src.includes(`'${x.replace(/'/g, "\\'")}':`));
  console.log(nema.join('\n'));
  console.error(`${nema.length} bez prijevoda od ${svi.length}`);
  process.exit(nema.length ? 1 : 0);
} else console.log(svi.join('\n'));
