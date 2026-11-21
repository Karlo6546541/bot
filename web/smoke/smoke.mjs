// Smoke test pravog HTML-a koji poslužuje `next start` uz lažni Supabase:
// SEO (naslov, opis, canonical, robots, JSON-LD, sitemap), lokacije (država,
// županija, grad), straničenje, preusmjeravanja i izgled na 375 px.
// Pokretanje: mock-supabase.mjs i `next start -p 3100` moraju raditi.
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';

const require = createRequire(import.meta.url);
const BASE = process.env.BASE ?? 'http://127.0.0.1:3100';
const OUT = new URL('./out/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });

let prosli = 0;
const pali = [];
const provjeri = (naziv, uvjet, detalj = '') => {
  if (uvjet) prosli++;
  else pali.push(`${naziv}${detalj ? ` — ${detalj}` : ''}`);
  console.log(`${uvjet ? '✓' : '✗'} ${naziv}${!uvjet && detalj ? ` — ${detalj}` : ''}`);
};

const dohvati = async (put, opts = {}) => {
  const r = await fetch(BASE + put, { redirect: 'manual', ...opts });
  return { status: r.status, loc: r.headers.get('location'), html: await r.text() };
};
const meta = (html, re) => html.match(re)?.[1];
const ukupno = (html) => Number(meta(html, /data-ukupno="(\d+)"/));
const brojKartica = (html) => (html.match(/class="plocica"/g) ?? []).length;
const jsonLd = (html) => [...html.matchAll(/<script type="application\/ld\+json">(.*?)<\/script>/gs)].map((m) => JSON.parse(m[1]));
const naslov = (html) => meta(html, /<title>(.*?)<\/title>/s);
const robots = (html) => meta(html, /<meta name="robots" content="(.*?)"/);
const canonical = (html) => meta(html, /<link rel="canonical" href="(.*?)"/);
const entitete = (s) => s?.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#x27;/g, "'");

// ---- sitemap: izvor adresa oglasa ----
const sm = await dohvati('/sitemap.xml');
const adrese = [...sm.html.matchAll(/<loc>(.*?)<\/loc>/g)].map((m) => m[1]);
const oglasi = adrese.filter((a) => a.includes('/oglas/')).map((a) => a.replace(BASE, ''));
provjeri('sitemap.xml sadrži oglase i kategorije', oglasi.length === 34 && adrese.some((a) => a.endsWith('/kategorija/kartice')), `oglasa: ${oglasi.length}`);
provjeri('sitemap ne sadrži prodani ni istekli oglas', !oglasi.some((o) => /alan-ford-broj-1-1$|alan-ford-broj-1-2$/.test(o)));

// ---- početna ----
const home = await dohvati('/');
provjeri('Početna: 200, naslov, opis i canonical', home.status === 200 && naslov(home.html)?.includes('Oglasnik za kolekcionare') && !!meta(home.html, /<meta name="description" content="(.{40,})"/) && !!canonical(home.html));
provjeri('Početna: JSON-LD WebSite s pretragom', jsonLd(home.html).some((j) => j['@type'] === 'WebSite' && j.potentialAction));
provjeri('Početna: 12 najnovijih oglasa u HTML-u', brojKartica(home.html) === 12, String(brojKartica(home.html)));
provjeri('Početna: jedan h1 i poveznice na kategorije', (home.html.match(/<h1/g) ?? []).length === 1 && (await dohvati('/kategorije')).html.includes('href="/kategorija/kartice/pokemon-i-ostali-tcg"'));

// ---- popis i filteri po lokaciji ----
const svi = await dohvati('/oglasi');
provjeri('Popis: 34 aktivna oglasa (bez prodanog i isteklog)', ukupno(svi.html) === 34, String(ukupno(svi.html)));
provjeri('Popis: 24 po stranici i veza na sljedeću', brojKartica(svi.html) === 24 && svi.html.includes('rel="next"'));
provjeri('Popis: bez filtera je indeksiran (nema noindex)', !robots(svi.html) && canonical(svi.html) === `${BASE}/oglasi`);
const str2 = await dohvati('/oglasi?stranica=2');
provjeri('Popis: 2. stranica ima 10 oglasa i vezu na prethodnu', brojKartica(str2.html) === 10 && str2.html.includes('rel="prev"') && canonical(str2.html) === `${BASE}/oglasi?stranica=2`);

const ba = await dohvati('/oglasi?drzava=BA');
provjeri('Filter država = BiH: 5 oglasa, svi u Sarajevu', ukupno(ba.html) === 5 && brojKartica(ba.html) === 5 && !ba.html.includes('Zagreb,'), String(ukupno(ba.html)));
provjeri('Filtrirani popis nije za indeks (noindex, follow)', robots(ba.html)?.includes('noindex'));
const ist = await dohvati('/oglasi?drzava=HR&zupanija=Istarska');
provjeri('Filter županija = Istarska: 5 oglasa u Puli', ukupno(ist.html) === 5 && ist.html.includes('Pula'), String(ukupno(ist.html)));
const sib = await dohvati('/oglasi?grad=sibenik');
provjeri('Filter grad "sibenik" (bez dijakritike) nalazi Šibenik', ukupno(sib.html) === 5 && sib.html.includes('Šibenik'), String(ukupno(sib.html)));
const kombo = await dohvati('/oglasi?drzava=HR&zupanija=Grad%20Zagreb&od=10&do=150&sort=cijena_rastuce');
const cijene = [...kombo.html.matchAll(/class="cijena">([^<]*)</g)].map((m) => Number(m[1].replace(/[^\d,]/g, '').replace(',', '.')));
provjeri('Kombinirani filteri: županija + cijena od-do + sortiranje daju rezultate', ukupno(kombo.html) > 0 && ukupno(kombo.html) === brojKartica(kombo.html) && cijene.every((c, i) => c >= 10 && c <= 150 && (i === 0 || c >= cijene[i - 1])), `${ukupno(kombo.html)}: ${cijene.join(',')}`);
provjeri('Kombinirani filteri: svi rezultati su u Zagrebu', (kombo.html.match(/data-mjesto="Zagreb, Grad Zagreb/g) ?? []).length === brojKartica(kombo.html));
const kat2 = await dohvati('/oglasi?kategorija=kartice&drzava=HR&od=5&do=200&sort=cijena_padajuce');
const c2 = [...kat2.html.matchAll(/class="cijena">([^<]*)</g)].map((m) => Number(m[1].replace(/[^\d,]/g, '').replace(',', '.')));
provjeri('Filter kategorija + država + cijena (padajuće)', ukupno(kat2.html) > 0 && c2.every((c, i) => i === 0 || c <= c2[i - 1]), c2.join(','));
provjeri('Filter prikazuje odabranu županiju u obrascu', /<option selected="">Grad Zagreb<\/option>/.test(kombo.html) && kombo.html.includes('<details class="ploca filteri filter-panel" open="">'));
provjeri('Bez aktivnih filtera okvir filtera je zatvoren (popis je prvi)', !svi.html.includes('<details class="ploca filteri filter-panel" open'));
const q = await dohvati('/oglasi?q=ljubljana');
provjeri('Pretraga teksta nalazi po gradu u opisu', ukupno(q.html) > 0 && q.html.includes('Ljubljana'), String(ukupno(q.html)));
const loš = await dohvati('/oglasi?drzava=XX1&sort=hakiraj&od=-5&stranica=abc');
provjeri('Neispravni parametri se ignoriraju (200, svi oglasi)', loš.status === 200 && ukupno(loš.html) === 34);

// ---- kategorija ----
const kat = await dohvati('/kategorija/novci/kovanice');
provjeri('Kategorija: naslov, canonical, breadcrumb JSON-LD, filteri kategorije', kat.status === 200 && naslov(kat.html)?.includes('Kovanice') && canonical(kat.html) === `${BASE}/kategorija/novci/kovanice` && jsonLd(kat.html).some((j) => j['@type'] === 'BreadcrumbList') && kat.html.includes('name="p_godina"'));
provjeri('Kategorija: samo oglasi te kategorije', brojKartica(kat.html) === 6 && ukupno(kat.html) === 6, String(ukupno(kat.html)));
provjeri('Nepostojeća kategorija: 404', (await dohvati('/kategorija/nema')).status === 404);

// ---- stranica oglasa ----
const nadi = (re) => oglasi.find((o) => re.test(o));
const hrPut = nadi(/charizard-base-set-1$/) ?? oglasi[0];
const hr = await dohvati(hrPut);
const ldHr = jsonLd(hr.html).find((j) => j['@type'] === 'Product');
provjeri('Oglas: naslov s cijenom, opis, canonical, jedan h1', hr.status === 200 && /Charizard.* – /.test(naslov(hr.html) ?? '') && canonical(hr.html) === BASE + hrPut && (hr.html.match(/<h1/g) ?? []).length === 1, naslov(hr.html));
provjeri('Oglas: Open Graph slika i opis', !!meta(hr.html, /<meta property="og:image" content="(.*?)"/) && !!meta(hr.html, /<meta property="og:description" content="(.{30,})"/));
provjeri('Oglas: JSON-LD Product s cijenom, EUR i dostupnošću', ldHr?.offers?.priceCurrency === 'EUR' && !!ldHr.offers.price && ldHr.offers.availability === 'https://schema.org/InStock');
provjeri('Oglas: lokacija u HTML-u (grad, županija, država)', hr.html.includes('Zagreb, Grad Zagreb, Hrvatska'));
const adr = ldHr?.offers?.availableAtOrFrom?.address;
provjeri('JSON-LD adresa: addressLocality, addressRegion, addressCountry=HR', !!adr?.addressLocality && !!adr.addressRegion && adr.addressCountry === 'HR', JSON.stringify(adr));
provjeri('Oglas: slični oglasi iste kategorije', hr.html.includes('Slični oglasi'));
const krivi = await dohvati(hrPut.replace(/[^/]+$/, 'krivi-slug'));
provjeri('Pogrešan slug: trajno preusmjeravanje na kanonsku adresu', krivi.status === 308 && krivi.loc?.endsWith(hrPut), `${krivi.status} ${krivi.loc}`);
const baPut = (await (async () => {
  const lista = await dohvati('/oglasi?drzava=BA');
  return meta(lista.html, /href="(\/oglas\/[^"]+)"/);
})());
const baOglas = await dohvati(baPut);
const adrBa = jsonLd(baOglas.html).find((j) => j['@type'] === 'Product')?.offers?.availableAtOrFrom?.address;
provjeri('Oglas izvan Hrvatske: "Sarajevo, Bosna i Hercegovina", bez regije', baOglas.html.includes('Sarajevo, Bosna i Hercegovina') && adrBa?.addressCountry === 'BA' && adrBa.addressRegion === undefined, JSON.stringify(adrBa));
const prodano = await dohvati('/oglasi?q=alan+ford+broj+1+%231');
provjeri('Prodani oglas nije u javnom popisu', !prodano.html.includes('Alan Ford broj 1 #1<'));
provjeri('Nepostojeći oglas: 404', (await dohvati('/oglas/11111111-1111-1111-1111-111111111111/x')).status === 404);
provjeri('Neispravan id oglasa: 404', (await dohvati('/oglas/nije-uuid/x')).status === 404);

// ---- profil prodavatelja, robots, privatne stranice ----
const kor = await dohvati(meta(hr.html, /href="(\/korisnik\/[^"]+)"/));
provjeri('Profil prodavatelja: ime i oglasi', kor.status === 200 && /Ana Kolekcionar|Luka/.test(kor.html) && brojKartica(kor.html) > 0);
const rb = await dohvati('/robots.txt');
provjeri('robots.txt: sitemap i zabrana privatnih stranica', rb.html.includes('Sitemap:') && rb.html.includes('Disallow: /poruke') && rb.html.includes('Disallow: /admin'));
for (const p of ['/objavi', '/poruke', '/moji-oglasi', '/favoriti', '/profil', '/admin']) {
  const r = await dohvati(p);
  provjeri(`Privatna ${p}: bez prijave vodi na prijavu`, [302, 303, 307, 308].includes(r.status) && !!r.loc?.includes('/prijava?natrag='), `${r.status} ${r.loc}`);
}
provjeri('Prijava i registracija su dostupne', (await dohvati('/prijava')).status === 200 && (await dohvati('/registracija')).status === 200);
for (const p of ['/uvjeti', '/privatnost', '/kontakt']) provjeri(`${p}: 200 s oznakom predloška`, (await dohvati(p)).html.includes('Predložak'));
const nema = await dohvati('/ne-postoji');
provjeri('Nepostojeća stranica: 404 s porukom', nema.status === 404 && nema.html.includes('Stranica nije pronađena'));
provjeri('Zaglavlja sigurnosti', (await fetch(BASE + '/')).headers.get('x-content-type-options') === 'nosniff');
provjeri('Bez riječi aukcija/licitiranje/košarica u HTML-u', ![home.html, svi.html, hr.html].some((h) => /aukcij|licitir|košaric/i.test(h.replace(/<script[\s\S]*?<\/script>/g, ''))));

// ---- izgled na mobitelu (375 px) ----
try {
  const { chromium } = require('playwright');
  const b = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
  const ctx = await b.newContext({ viewport: { width: 375, height: 800 }, deviceScaleFactor: 2, isMobile: true });
  const page = await ctx.newPage();
  const greske = [];
  page.on('pageerror', (e) => greske.push(e.message));
  const slike = [
    ['pocetna', '/'],
    ['popis-bih', '/oglasi?drzava=BA'],
    ['popis-filteri', '/oglasi?drzava=HR&zupanija=Grad%20Zagreb&od=10&do=150'],
    ['kategorija', '/kategorija/kartice'],
    ['oglas', hrPut],
    ['oglas-bih', baPut],
    ['objavi-prijava', '/prijava'],
  ];
  for (const [ime, put] of slike) {
    await page.goto(BASE + put, { waitUntil: 'networkidle' });
    const { sirina, prozor } = await page.evaluate(() => ({ sirina: document.documentElement.scrollWidth, prozor: window.innerWidth }));
    provjeri(`Mobitel 375 px: ${ime} bez horizontalnog pomicanja`, sirina <= prozor, `${sirina}/${prozor}`);
    await page.screenshot({ path: `${OUT}${ime}.png`, fullPage: true });
  }
  // Obrazac filtera: promjena države mijenja županiju (padajući popis ↔ slobodno polje).
  await page.goto(BASE + '/oglasi', { waitUntil: 'networkidle' });
  await page.click('summary:has-text("Pretraga i filteri")');
  provjeri('Filter: županija je padajući popis od 21 županije (+ "Sve")', (await page.locator('select[name=zupanija] option').count()) === 22);
  await page.selectOption('select[name=drzava]', 'BA');
  provjeri('Filter: izvan Hrvatske županija postaje slobodna "regija"', (await page.locator('input[name=zupanija]').count()) === 1 && (await page.locator('select[name=zupanija]').count()) === 0);
  await page.selectOption('select[name=drzava]', 'HR');
  provjeri('Filter: povratak na Hrvatsku vraća popis županija', (await page.locator('select[name=zupanija] option').count()) === 22);
  await page.fill('input[name=grad]', 'Split');
  await page.click('button:has-text("Primijeni")');
  await page.waitForURL(/grad=Split/);
  provjeri('Filter: obrazac šalje grad i filtrira rezultate (GET)', page.url().includes('drzava=HR') && ukupno(await page.content()) > 0, page.url());
  provjeri('Bez grešaka u pregledniku', greske.length === 0, greske.slice(0, 2).join(' | '));
  await b.close();
} catch (e) {
  provjeri('Izgled na mobitelu (Playwright)', false, String(e.message).split('\n')[0]);
}

console.log(`\n${prosli}/${prosli + pali.length} provjera prošlo`);
if (pali.length) console.log('PALE:\n- ' + pali.join('\n- '));
process.exit(pali.length ? 1 : 0);
