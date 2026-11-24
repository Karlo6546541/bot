// Kriteriji prihvaćanja u pravom pregledniku (lokalni način, mobitel 375 px):
// registracija, objava s fotografijom, pretraga, poruka prodavatelju,
// prijava oglasa i moderacija; bez horizontalnog pomicanja i bez riječi
// iz aukcija/košarice. Pokretanje: npm run build && npm run e2e
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { extname, join } from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const DIST = new URL('../dist/', import.meta.url).pathname;
const OUT = new URL('./out/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });
const BASE = '/bot';
const ZABRANJENO = /aukcij|licitir|licitacij|košaric|kosaric|protuponud|najviša ponuda|ponudi cijenu|dodaj u košaricu|naplat|plaćanje karticom/i;

// Poslužitelj kao GitHub Pages: nepostojeća adresa dobiva 404.html.
const TIPOVI = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.txt': 'text/plain' };
const server = createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (!p.startsWith(BASE)) return res.writeHead(404).end();
  p = p.slice(BASE.length) || '/';
  let f = join(DIST, p.endsWith('/') ? `${p}index.html` : p);
  let status = 200;
  if (!existsSync(f) || !extname(f)) {
    f = join(DIST, '404.html');
    status = 404;
  }
  res.writeHead(status, { 'content-type': TIPOVI[extname(f)] ?? 'application/octet-stream' });
  res.end(readFileSync(f));
}).listen(8766);

const rezultati = [];
const provjeri = (naziv, uvjet, detalj = '') => {
  rezultati.push({ naziv, ok: !!uvjet, detalj });
  console.log(`${uvjet ? '✓' : '✗'} ${naziv}${detalj ? ` — ${detalj}` : ''}`);
};

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 375, height: 760 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await ctx.newPage();
const greske = [];
page.on('pageerror', (e) => greske.push(e.message));
page.on('console', (m) => m.type() === 'error' && !/status of 404/.test(m.text()) && greske.push(m.text()));
// Izravne adrese na GitHub Pages dolaze kao 404.html (očekivano); ostali resursi moraju postojati.
page.on('response', (r) => r.status() >= 400 && r.request().resourceType() !== 'document' && greske.push(`${r.status()} ${r.url()}`));
const url = (p) => `http://localhost:8766${BASE}${p}`;

const posjeceno = new Set();
async function pregledStranice(naziv) {
  await page.waitForTimeout(250);
  const { sirina, prozor, tekst } = await page.evaluate(() => ({
    sirina: document.documentElement.scrollWidth,
    prozor: window.innerWidth,
    tekst: document.body.innerText,
  }));
  const rijec = tekst.match(ZABRANJENO);
  provjeri(`${naziv}: bez horizontalnog pomicanja`, sirina <= prozor, `${sirina}px / ${prozor}px`);
  provjeri(`${naziv}: bez riječi aukcija/licitiranje/košarica`, !rijec, rijec?.[0] ?? '');
  if (!posjeceno.has(naziv)) {
    posjeceno.add(naziv);
    await page.screenshot({ path: `${OUT}${String(posjeceno.size).padStart(2, '0')}-${naziv.replace(/\W+/g, '-')}.png`, fullPage: true });
  }
}

async function registriraj(ime, email) {
  await page.goto(url('/registracija'));
  await page.fill('input[name=ime]', ime);
  await page.fill('input[name=email]', email);
  await page.fill('input[name=lozinka]', 'lozinka123');
  await page.check('input[name=uvjeti]');
  await page.click('button[type=submit]');
  await page.waitForSelector('a[aria-label="Moj profil"]');
}
async function odjava() {
  await page.goto(url('/profil'));
  await page.click('text=Odjava');
  await page.waitForSelector('a.gumb:has-text("Prijava")');
}

try {
  // 1. Početna
  await page.goto(url('/'));
  await page.waitForSelector('text=Kategorije');
  provjeri('Početna: slogan "Oglasnik za kolekcionare"', await page.isVisible('h1:has-text("Oglasnik za kolekcionare")'));
  provjeri('Početna: gumb "Objavi oglas" vidljiv', (await page.locator('a:has-text("Objavi oglas"):visible').count()) > 0);
  provjeri('Početna: 7 kategorija', (await page.locator('.kategorija-plocica').count()) === 7);
  await pregledStranice('pocetna');

  // 2. Registracija prodavatelja i objava s fotografijom
  await registriraj('Ana Kolekcionar', 'ana@primjer.hr');
  provjeri('Registracija prodavatelja', true);
  await page.goto(url('/objavi'));
  await page.waitForSelector('input[name=naslov]');
  await pregledStranice('objava');
  // Fotografija: snimka dijela ekrana kao PNG.
  const png = await page.screenshot({ clip: { x: 0, y: 0, width: 300, height: 300 } });
  await page.setInputFiles('input[data-unos-slika]', { name: 'charizard.png', mimeType: 'image/png', buffer: png });
  await page.waitForSelector('.slike-obrazac img');
  await page.fill('input[name=naslov]', 'Charizard Base Set 4/102 holo');
  await page.selectOption('select[name=kategorija]', 'kartice');
  await page.selectOption('select[name=p_igra]', 'Pokémon');
  await page.fill('input[name=p_set]', 'Base Set');
  await page.check('input[name=stanje][value="Dobro"]');
  await page.fill('textarea[name=opis]', 'Originalna kartica iz 1999., lagano izlizani rubovi, bez savijanja.');
  await page.fill('input[name=cijena]', '250');
  await page.selectOption('select[name=zupanija]', 'Grad Zagreb');
  await page.fill('input[name=grad]', 'Zagreb');
  await page.click('button:has-text("Pregled oglasa")');
  await page.waitForSelector('[data-pregled]');
  provjeri('Pregled oglasa prije objave', await page.isVisible('[data-pregled] h2:has-text("Charizard")'));
  await pregledStranice('pregled');
  await page.click('button:has-text("Objavi oglas")');
  await page.waitForURL(/\/oglas\/[^/]+\/charizard-base-set-4-102-holo$/);
  await page.waitForSelector('h1:has-text("Charizard Base Set")');
  await page.waitForFunction(() => document.title.startsWith('Charizard'));
  provjeri('Objava oglasa s fotografijom', await page.isVisible('h1:has-text("Charizard Base Set")'));
  provjeri('Čista adresa oglasa', /\/bot\/oglas\/[0-9a-f-]+\/charizard-base-set-4-102-holo$/.test(page.url()), page.url());
  provjeri('SEO naslov stranice oglasa', (await page.title()).startsWith('Charizard Base Set 4/102 holo'), await page.title());
  const opis = await page.getAttribute('meta[name=description]', 'content');
  provjeri('SEO opis stranice oglasa', opis?.includes('Charizard') && opis.length <= 160, opis ?? '');
  await pregledStranice('oglas-vlasnik');
  const oglasUrl = page.url();

  // 3. Kupac: registracija, pretraga, poruka
  await odjava();
  await registriraj('Marko Kupac', 'marko@primjer.hr');
  await page.goto(url('/'));
  await page.fill('#trazi', 'charizard');
  await page.click('button:has-text("Traži")');
  await page.waitForURL(/\/oglasi\?q=charizard/);
  await page.waitForSelector('.kartica');
  provjeri('Pretraga pronalazi oglas', (await page.locator('.kartica').count()) === 1);
  await pregledStranice('pretraga');
  await page.goto(url('/oglasi?q=charizard&kategorija=kartice&p_igra=Magic'));
  await page.waitForSelector('text=Nema oglasa za ovu pretragu');
  provjeri('Filter polja kategorije (igra: Magic) isključuje oglas', true);
  await page.goto(url('/kategorija/kartice?od=100&do=300&sort=cijena_rastuce'));
  await page.waitForSelector('.kartica');
  provjeri('Kategorija + cijena od-do + sortiranje', (await page.locator('.kartica').count()) === 1);
  await pregledStranice('kategorija');

  await page.goto(oglasUrl);
  await page.waitForSelector('text=Sigurna kupnja');
  provjeri('Upozorenje o sigurnoj kupnji', await page.isVisible('text=osobno preuzimanje'));
  await pregledStranice('oglas-kupac');
  await page.click('button:has-text("Spremi")');
  await page.waitForSelector('button:has-text("Spremljeno")');
  await page.click('button:has-text("Pošalji poruku")');
  await page.waitForURL(/\/poruke\/.+/);
  await page.waitForSelector('.mjehur.moj');
  provjeri('Poruka prodavatelju poslana', await page.isVisible('.mjehur.moj:has-text("Je li još dostupno")'));
  await pregledStranice('razgovor');
  await page.goto(url('/favoriti'));
  await page.waitForSelector('.kartica');
  provjeri('Favoriti', (await page.locator('.kartica').count()) === 1);

  // 4. Prijava oglasa
  await page.goto(oglasUrl);
  await page.click('button:has-text("Prijavi oglas")');
  await page.check('input[name=razlog][value=krivotvorina]');
  await page.click('button:has-text("Pošalji prijavu")');
  await page.waitForSelector('text=Prijava je poslana');
  provjeri('Prijava oglasa s razlogom', true);

  // 5. Prodavatelj: poruka u inboxu, odgovor, moji oglasi, moderacija
  await odjava();
  await page.goto(url('/prijava'));
  await page.fill('input[name=email]', 'ana@primjer.hr');
  await page.fill('input[name=lozinka]', 'lozinka123');
  await page.click('button[type=submit]');
  await page.waitForSelector('a[aria-label="Moj profil"]');
  provjeri('Značka nepročitane poruke', await page.isVisible('.znacka'));
  await page.goto(url('/poruke'));
  await page.waitForSelector('.redak');
  await pregledStranice('poruke');
  await page.click('.redak');
  await page.fill('#poruka', 'Dostupno je, može osobno u Zagrebu.');
  await page.click('button:has-text("Pošalji")');
  await page.waitForSelector('.mjehur.moj:has-text("Dostupno je")');
  provjeri('Prodavatelj odgovara u razgovoru', true);
  await page.goto(url('/moji-oglasi'));
  await page.waitForSelector('[data-moj-oglas]');
  await pregledStranice('moji-oglasi');
  await page.click('button:has-text("Produlji")');
  await page.waitForSelector('text=produljen');
  provjeri('Produlji oglas', true);
  await page.click('button:has-text("Kontakti")');
  await page.waitForSelector('text=1 poruka');
  provjeri('Povijest kontakata po oglasu', true);
  await page.keyboard.press('Escape');
  await page.goto(url('/admin'));
  await page.waitForSelector('[data-prijava]');
  provjeri('Admin vidi prijavljeni oglas', await page.isVisible('[data-prijava]:has-text("Krivotvorina")'));
  await pregledStranice('admin');
  await page.click('button:has-text("Korisnici")');
  await page.waitForSelector('table.admin');
  await pregledStranice('admin-korisnici');
  await page.click('button:has-text("Prijavljeni oglasi")');
  await page.goto(url('/moji-oglasi'));
  await page.click('button:has-text("Označi kao prodano")');
  await page.fill('.dijalog input', '240');
  await page.click('.dijalog button:has-text("Označi prodano")');
  await page.waitForSelector('text=Nemaš aktivnih oglasa');
  await page.click('[role=tab]:has-text("Prodani")');
  provjeri('Označi kao prodano s konačnom cijenom', await page.isVisible('text=za 240'));

  // 6. Pravne stranice i 404
  for (const p of ['uvjeti', 'privatnost', 'kontakt']) {
    await page.goto(url(`/${p}`));
    await page.waitForSelector('.napomena');
    provjeri(`/${p}: oznaka da tekst pregleda pravnik`, await page.isVisible('text=mora ga pregledati pravnik'));
    await pregledStranice(p);
  }
  await page.goto(url('/ne-postoji'));
  provjeri('Nepostojeća stranica', await page.isVisible('text=Stranica nije pronađena'));

  // 7. Ni u izgrađenom kodu nema tekstova aukcija i košarice.
  const js = readdirSync(join(DIST, 'assets')).map((f) => readFileSync(join(DIST, 'assets', f), 'utf8')).join('\n');
  const uKodu = js.match(ZABRANJENO);
  provjeri('Izgrađeni kod: bez tekstova aukcija i košarice', !uKodu, uKodu?.[0] ?? '');
  provjeri('Bez grešaka u konzoli', greske.length === 0, greske.slice(0, 3).join(' | '));
} catch (e) {
  provjeri('Tijek je prošao do kraja', false, e.message.split('\n').slice(0, 4).join(' ') + ' @ ' + page.url());
  await page.screenshot({ path: `${OUT}greska.png`, fullPage: true });
} finally {
  await browser.close();
  server.close();
}
const pali = rezultati.filter((r) => !r.ok);
console.log(`\n${rezultati.length - pali.length}/${rezultati.length} provjera prošlo`);
process.exit(pali.length ? 1 : 0);
