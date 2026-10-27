const {chromium} = require('/tmp/feed-browser/node_modules/playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox'],
  });
  try {
    for (const [name, width, height] of [
      ['mobile-320', 320, 740], ['mobile-390', 390, 844], ['desktop', 1440, 1000],
    ]) {
      const context = await browser.newContext({viewport: {width, height}});
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto('http://127.0.0.1:8765/bot/', {waitUntil: 'networkidle'});
      await page.waitForSelector('flutter-view', {timeout: 30000});
      await page.waitForTimeout(4500);
      const screenshot = await page.screenshot({type: 'jpeg', quality: 75});
      console.log(`FEED_SCREENSHOT:${name}:${screenshot.toString('base64')}`);
      if (errors.length) throw new Error(errors.join('\n'));
      await context.close();
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
