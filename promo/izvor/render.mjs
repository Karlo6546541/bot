import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const dir = new URL('./', import.meta.url).pathname;
mkdirSync(dir + 'frames', { recursive: true });
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
await p.goto('file://' + dir + 'index.html');
await p.evaluate(() => document.fonts.ready);
const FPS = 30, N = 15 * FPS;
const only = process.argv[2] ? process.argv[2].split(',').map(Number) : null;
for (let i = 0; i < N; i++) {
  if (only && !only.includes(i)) continue;
  const t = i / FPS;
  await p.evaluate((t) => window.render(t), t);
  await p.screenshot({ path: `${dir}frames/f_${String(i).padStart(4, '0')}.jpg`, type: 'jpeg', quality: 92 });
}
await b.close();
console.log('gotovo');
