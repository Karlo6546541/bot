// Isolated, offline fixture. No real payment or production account is touched.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/tmp/feed-browser/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const base = process.env.PREVIEW_BASE_URL || 'http://127.0.0.1:8765/bot/';
const output = process.env.PREVIEW_ARTIFACT_DIR || '/tmp/feed-preview/screenshots';
const scenarios = [
  ['home', 320, 740, 'light', 'Traži na Subhastu'],
  ['home', 390, 844, 'light', 'Uživo'],
  ['home', 1440, 1000, 'light', 'Uživo'],
  ['home', 390, 844, 'dark', 'Uživo'],
  ['live', 320, 740, 'light', 'Shop'],
  ['live', 390, 844, 'light', 'Shop'],
  ['host', 390, 844, 'dark', 'Shop'],
  ['shop', 390, 844, 'light', 'Shop ('],
  ['shop', 1440, 900, 'light', 'Shop ('],
  ['categories', 390, 844, 'light', 'Konzole'],
  ['activity', 390, 844, 'light', 'Kupnje'],
  ['profile', 390, 844, 'light', 'Pogledaj profil'],
  ['seller', 390, 844, 'light', 'Prodavač'],
  ['form', 390, 844, 'light', 'Spremi podatke'],
  ['form', 1440, 900, 'light', 'Spremi podatke'],
  ['listing', 390, 844, 'light', 'Kupi odmah'],
  ['messages', 390, 844, 'light', 'Poruke'],
  ['notifications', 390, 844, 'light', 'Obavijesti'],
  ['finance', 390, 844, 'light', 'Financije'],
  ['login', 390, 844, 'light', 'Prijavi se'],
  ['seller', 390, 844, 'dark', 'Prodavač'],
  ['profile', 390, 844, 'dark', 'Pogledaj profil'],
  ['shop', 390, 844, 'dark', 'Shop ('],
  ['form', 390, 844, 'dark', 'Spremi podatke'],
  ['listing', 390, 844, 'dark', 'Kupi odmah'],
  ['categories', 390, 844, 'dark', 'Konzole'],
  ['activity', 390, 844, 'dark', 'Kupnje'],
  ['purchase', 390, 844, 'dark', 'Potvrdi kupnju'],
  ['purchase', 320, 740, 'light', 'Potvrdi kupnju'],
];
(async () => {
  fs.mkdirSync(output, {recursive:true});
  const browser = await chromium.launch({executablePath:process.env.CHROME_PATH || '/usr/bin/google-chrome',headless:true,args:['--no-sandbox'],...(process.env.PREVIEW_PROXY ? {proxy:{server:process.env.PREVIEW_PROXY}} : {})});
  try {
    for (const [route,width,height,theme,expected] of scenarios.filter(s => !process.env.PREVIEW_ROUTES || process.env.PREVIEW_ROUTES.split(',').includes(s[0]))) {
      const context = await browser.newContext({viewport:{width,height},serviceWorkers:'block'});
      const page = await context.newPage();
      // Managed browser proxies do not serve loopback URLs. Fulfil local build
      // assets directly from disk; external photos still use the configured proxy.
      if (process.env.PREVIEW_WEB_ROOT) {
        const root = path.resolve(process.env.PREVIEW_WEB_ROOT);
        await page.route(`${new URL(base).origin}/**`, async request => {
          const name = decodeURIComponent(new URL(request.request().url()).pathname).replace(new URL(base).pathname,'') || 'index.html';
          const file = path.resolve(root,name);
          if (!file.startsWith(root + path.sep)) return request.fulfill({status:403,body:'Invalid path'});
          const mime = {'.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.html':'text/html','.png':'image/png','.ttf':'font/ttf','.woff2':'font/woff2'}[path.extname(file)] || 'application/octet-stream';
          try { await request.fulfill({status:200,body:fs.readFileSync(file),contentType:mime}); }
          catch { await request.fulfill({status:404,body:'Missing asset'}); }
        });
      }
      const errors=[]; page.on('pageerror',e=>errors.push(e.message));
      await page.goto(`${base}?preview=${route}&theme=${theme}`,{waitUntil:'networkidle'});
      await page.waitForSelector('flutter-view');
      try { await page.waitForFunction(text => (document.body.innerText + ' ' + Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join(' ')).includes(text), expected, {timeout:20000}); } catch (error) { console.error(await page.locator('body').ariaSnapshot()); await page.screenshot({path:path.join(output,`failed-${route}.png`)}); throw error; }
      await page.waitForTimeout(3000);
      await page.screenshot({path:path.join(output,`${route}-${width}-${theme}.png`)});
      if (route === 'profile') {
        await page.getByRole('button',{name:/Pogledaj profil/}).click();
        await page.getByRole('button',{name:'Sviđa mi se',exact:true}).waitFor();
        await page.getByRole('button',{name:'Postavke',exact:true}).click();
        await page.getByRole('button',{name:'Natrag',exact:true}).waitFor();
      }
      if (route === 'live' && width === 390) {
        await page.getByRole('button',{name:/^Shop/}).first().click();
        await page.getByRole('tab',{name:/^Shop/}).click();
        await page.getByRole('button',{name:'Kupi',exact:true}).first().waitFor();
        await page.screenshot({path:path.join(output,'live-shop-drawer.png')});
      }
      if (route === 'home' && width === 390 && theme === 'light') {
        await page.getByRole('button',{name:'Filteri',exact:true}).click();
        await page.getByText('Digitalne kupnje',{exact:true}).waitFor();
      }
      if (errors.length) throw Error(errors.join('\n'));
      console.log(`PASS ${route} ${width} ${theme}`);
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(error => {console.error(error);process.exitCode=1;});
