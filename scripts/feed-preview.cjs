const {chromium} = require('/tmp/feed-browser/node_modules/playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox'],
  });
  try {
    for (const [name, width, height] of [
      ['mobile-320', 320, 740], ['mobile-390', 390, 844], ['mobile-short', 390, 600], ['desktop', 1440, 1000],
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
      if (name === 'mobile-390') {
        await page.evaluate(() => {
          window.feedFrames = [];
          let previous;
          function tick(at) {
            if (previous) window.feedFrames.push(at - previous);
            previous = at;
            window.feedFrameRequest = requestAnimationFrame(tick);
          }
          window.feedFrameRequest = requestAnimationFrame(tick);
        });
        for (let swipe = 0; swipe < 3; swipe++) {
          await page.mouse.move(width * 0.45, height * 0.55);
          await page.mouse.down();
          await page.mouse.move(width * 0.45, height * 0.15, {steps: 15});
          await page.mouse.up();
          await page.waitForTimeout(450);
        }
        const frames = await page.evaluate(() => {
          cancelAnimationFrame(window.feedFrameRequest);
          const values = window.feedFrames.sort((a, b) => a - b);
          return {count: values.length, p95ms: values[Math.floor(values.length * 0.95)], maxms: values.at(-1)};
        });
        console.log('FEED_SCROLL_FRAMES:' + JSON.stringify(frames));
        // Coordinates address the fixed header in this isolated 390 px fixture.
        await page.mouse.click(width - 60, 64);
        await page.waitForTimeout(500);
        console.log('FEED_SCREENSHOT:auctions:' + (await page.screenshot({type: 'jpeg', quality: 75})).toString('base64'));
        await page.mouse.click((width - 96) * 5 / 6, 32);
        await page.waitForTimeout(500);
        console.log('FEED_SCREENSHOT:live-browse:' + (await page.screenshot({type: 'jpeg', quality: 75})).toString('base64'));
        await page.mouse.click(80, 72);
        await page.waitForTimeout(500);
        console.log('FEED_SCREENSHOT:live-category-picker:' + (await page.screenshot({type: 'jpeg', quality: 75})).toString('base64'));
      }
      if (errors.length) throw new Error(errors.join('\n'));
      await context.close();
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
