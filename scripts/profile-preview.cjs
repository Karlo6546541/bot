const {chromium} = require('/tmp/feed-browser/node_modules/playwright');
(async () => {
  const browser = await chromium.launch({executablePath: '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox']});
  try {
    for (const [name, width, height] of [['profile-320', 320, 740], ['profile-390', 390, 844], ['profile-short', 390, 600], ['profile-desktop', 1440, 1000]]) {
      const context = await browser.newContext({viewport: {width, height}});
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto('http://127.0.0.1:8765/bot/?preview=profile', {waitUntil: 'networkidle'});
      await page.waitForSelector('flutter-view', {timeout: 30000});
      await page.getByRole('button', {name: 'Sviđa mi se', exact: true}).waitFor({timeout: 20000});
      await page.waitForTimeout(1000);
      const capture = async suffix => console.log(`FEED_SCREENSHOT:${name}${suffix}:` + (await page.screenshot({type: 'jpeg', quality: 75})).toString('base64'));
      await capture('');
      await page.getByRole('button', {name: 'Sviđa mi se', exact: true}).click();
      await page.waitForTimeout(400);
      await capture('-liked');
      await page.getByRole('button', {name: 'Postavke', exact: true}).click();
      await page.waitForTimeout(400);
      await capture('-settings');
      if (errors.length) throw new Error(errors.join('\n'));
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
