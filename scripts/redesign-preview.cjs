// Isolated, offline fixture. No real payment or production account is touched.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/tmp/feed-browser/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const base = process.env.PREVIEW_BASE_URL || 'http://127.0.0.1:8765/bot/';
const output = process.env.PREVIEW_ARTIFACT_DIR || '/tmp/feed-preview/screenshots';
const scenarios = [
  ['home', 320, 740, 'light', 'Subhasto'],
  ['home', 390, 844, 'light', 'Subhasto'],
  ['home', 1440, 1000, 'light', 'Subhasto'],
  ['home', 390, 844, 'dark', 'Subhasto'],
  ['live', 320, 740, 'light', 'Povuci gore za shop'],
  ['live', 390, 844, 'light', 'Povuci gore za shop'],
  ['host', 390, 844, 'dark', 'Povuci gore za shop'],
  ['shop', 390, 844, 'light', 'Shop ('],
  ['shop', 1440, 900, 'light', 'Shop ('],
  ['categories', 390, 844, 'light', 'Konzole'],
  ['activity', 390, 844, 'light', 'Kupnje'],
  ['activity', 320, 740, 'dark', 'Kupnje'],
  ['studio', 390, 844, 'dark', 'Pokreni live'],
  ['studio', 320, 740, 'light', 'Pokreni live'],
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
  ['inventory', 390, 844, 'dark', 'Inventar'],
  ['inventory', 320, 740, 'light', 'Inventar'],
  ['shipping', 390, 844, 'dark', 'Otprema'],
  ['health', 390, 844, 'dark', 'Zdravlje računa'],
  ['history', 390, 844, 'dark', 'Povijest transakcija'],
  ['search', 390, 844, 'dark', 'Pretraži'],
  ['wallet', 390, 844, 'dark', 'Novčanik'],
  ['wallet', 320, 740, 'light', 'Novčanik'],
  ['sales', 390, 844, 'dark', 'Prodaja'],
  ['settings', 390, 844, 'dark', 'Postavke'],
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
      await page.mouse.move(1,1);
      await page.waitForTimeout(3000);
      await page.screenshot({path:path.join(output,`${route}-${width}-${theme}.png`)});
      if (route === 'profile') {
        await page.getByRole('button',{name:/Pogledaj profil/}).click();
        await page.getByRole('button',{name:'Sviđa mi se',exact:true}).waitFor();
        await page.getByRole('button',{name:'Postavke',exact:true}).click();
        await page.getByRole('button',{name:'Natrag',exact:true}).waitFor();
      }
      if (route === 'live' && width === 390) {
        const handle = page.getByRole('button',{name:/Povuci gore za shop/}).first();
        const box = await handle.boundingBox();
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await page.mouse.down(); await page.mouse.move(box.x + box.width / 2, box.y - 140,{steps:12}); await page.mouse.up();
        await page.getByRole('tab',{name:/^Kupi odmah/}).click();
        await page.getByRole('button',{name:'Kupi odmah',exact:true}).first().waitFor();
        await page.screenshot({path:path.join(output,'live-shop-drawer.png')});
        const closeHandle = await page.getByRole('button',{name:'Zatvori shop',exact:true}).boundingBox();
        await page.mouse.move(width / 2, closeHandle.y + closeHandle.height / 2);
        await page.mouse.down(); await page.mouse.move(width / 2,closeHandle.y+160,{steps:12}); await page.mouse.up();
        await handle.waitFor();
      }
      if (route === 'home' && width === 390 && theme === 'dark') {
        // Three destinations are real top-level tabs. No modal is needed.
        await page.getByRole('tab',{name:/Studio/}).last().click();
        await page.getByRole('button',{name:'Pokreni live',exact:true}).waitFor();
        await page.screenshot({path:path.join(output,'home-studio.png')});
        await page.getByRole('tab',{name:/Trezor/}).last().click();
        await page.getByRole('button',{name:/Kupnje/}).first().waitFor();
        await page.screenshot({path:path.join(output,'home-vault.png')});
        await page.getByRole('tab',{name:/Pozornica/}).last().click();
        await page.getByRole('button',{name:'Pretraži',exact:true}).click();
        await page.getByRole('textbox').first().fill('Satovi');
        await page.waitForTimeout(300);
        await page.screenshot({path:path.join(output,'home-inline-search.png')});
      }
      if (route === 'activity' && width === 390 && theme === 'light') {
        const touch = await context.newCDPSession(page);
        await touch.send('Emulation.setTouchEmulationEnabled',{enabled:true});
        await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:180,y:550}]});
        await touch.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:180,y:350}]});
        await page.getByRole('button',{name:'Otvori navigaciju',exact:true}).waitFor();
        await page.screenshot({path:path.join(output,'vault-dock-collapsed.png')});
        await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
        await page.getByRole('tab',{name:/Trezor/}).waitFor();
        await page.screenshot({path:path.join(output,'vault-dock-idle.png')});
        await touch.detach();
      }
      if (route === 'finance') {
        await page.getByRole('tab',{name:'Transakcije',exact:true}).click();
        await page.mouse.move(1,1);
        await page.waitForTimeout(350);
        await page.screenshot({path:path.join(output,'finance-transaction-deck.png')});
        await page.getByRole('tab',{name:'Izvještaji',exact:true}).click();
        await page.getByRole('button',{name:'Pregled izvještaja',exact:true}).first().click();
        await page.getByRole('button',{name:'Izvezi CSV',exact:true}).waitFor();
        await page.mouse.move(1,1);
        await page.screenshot({path:path.join(output,'finance-monthly-peek.png')});
      }
      if (route === 'search') {
        await page.getByRole('textbox').first().fill('sat');
        await page.getByRole('tab',{name:'Top',exact:true}).waitFor();
        await page.screenshot({path:path.join(output,'spotlight-results.png')});
      }
      if (route === 'home' && width === 390 && theme === 'light') {
        if (await page.getByRole('button',{name:'Računi',exact:true}).count()) await page.getByRole('button',{name:'Pretraži',exact:true}).click();
        await page.getByRole('button',{name:'Filteri',exact:true}).click();
        await page.getByText('Digitalne kupnje',{exact:true}).waitFor();
      }
      if (errors.length) throw Error(errors.join('\n'));
      console.log(`PASS ${route} ${width} ${theme}`);
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(error => {console.error(error);process.exitCode=1;});
