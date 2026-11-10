/**
 * Dev-only: renders placeholder covers, pages and PWA icons with the
 * pre-installed Chromium. Output is committed, so `npm run seed` does not need
 * a browser. Run: npx tsx scripts/generate-seed-assets.ts
 */
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import path from "node:path";
import { PAGES_PER_CHAPTER, seedSeries } from "./seed-data";

const root = path.resolve(__dirname, "..");
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");

function coverHtml(title: string, [a, b, c]: string[]) {
  return `<div style="width:600px;height:900px;background:linear-gradient(160deg,${a},${b});position:relative;font-family:Georgia,serif;overflow:hidden">
    <svg width="600" height="900" style="position:absolute;inset:0">
      <circle cx="420" cy="260" r="170" fill="${c}" opacity=".85"/>
      <polygon points="0,900 0,620 120,560 220,640 330,520 450,610 600,540 600,900" fill="#000" opacity=".55"/>
      <polygon points="0,900 0,720 160,680 300,740 470,670 600,720 600,900" fill="#000" opacity=".7"/>
    </svg>
    <div style="position:absolute;left:40px;right:40px;bottom:70px;color:#fff;font-size:58px;font-weight:bold;line-height:1.05;text-shadow:0 3px 12px #000">${esc(title)}</div>
  </div>`;
}

function pageHtml(title: string, n: number, [a, b, c]: string[]) {
  const panels = [
    `<rect x="30" y="30" width="740" height="360" rx="6" fill="${a}"/><circle cx="${200 + n * 90}" cy="190" r="90" fill="${c}"/>`,
    `<rect x="30" y="410" width="360" height="380" rx="6" fill="${b}"/><rect x="410" y="410" width="360" height="380" rx="6" fill="${a}" opacity=".8"/>
     <ellipse cx="210" cy="560" rx="110" ry="40" fill="#fff"/><text x="210" y="570" font-size="26" text-anchor="middle" font-family="Comic Sans MS,sans-serif">Hej!</text>
     <polygon points="480,760 590,520 700,760" fill="${c}"/>`,
    `<rect x="30" y="810" width="740" height="360" rx="6" fill="${b}" opacity=".9"/>
     <ellipse cx="560" cy="900" rx="180" ry="50" fill="#fff"/><text x="560" y="910" font-size="24" text-anchor="middle" font-family="Comic Sans MS,sans-serif">Što se ovdje događa?</text>`,
  ].join("");
  return `<div style="width:800px;height:1200px;background:#f4f1ea">
    <svg width="800" height="1200" style="display:block">${panels}
      <rect x="30" y="30" width="740" height="360" rx="6" fill="none" stroke="#111" stroke-width="6"/>
      <rect x="30" y="410" width="360" height="380" rx="6" fill="none" stroke="#111" stroke-width="6"/>
      <rect x="410" y="410" width="360" height="380" rx="6" fill="none" stroke="#111" stroke-width="6"/>
      <rect x="30" y="810" width="740" height="360" rx="6" fill="none" stroke="#111" stroke-width="6"/>
      <text x="60" y="80" font-size="30" font-family="Georgia,serif" fill="#fff" font-weight="bold">${esc(title)}</text>
      <text x="740" y="1150" font-size="28" text-anchor="end" font-family="Georgia,serif" fill="#111">${n}</text>
    </svg></div>`;
}

function iconHtml(size: number, maskable: boolean) {
  const pad = maskable ? size * 0.2 : 0;
  return `<div style="width:${size}px;height:${size}px;background:#e4572e;display:grid;place-items:center;border-radius:${maskable ? 0 : size * 0.2}px">
    <div style="font-family:Arial Black,Arial,sans-serif;font-weight:900;color:#fff;font-size:${(size - pad * 2) * 0.62}px;line-height:1">K</div></div>`;
}

async function main() {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const shot = async (html: string, file: string, type: "jpeg" | "png") => {
    await page.setContent(`<body style="margin:0">${html}</body>`);
    mkdirSync(path.dirname(file), { recursive: true });
    await page.locator("body > div").screenshot({ path: file, type, ...(type === "jpeg" ? { quality: 72 } : {}) });
    console.log("wrote", path.relative(root, file));
  };
  for (const s of seedSeries) {
    const dir = path.join(root, "supabase/seed-assets", s.slug);
    await shot(coverHtml(s.title, s.palette), path.join(dir, "cover.jpg"), "jpeg");
    for (let n = 1; n <= PAGES_PER_CHAPTER; n++) {
      await shot(pageHtml(s.title, n, s.palette), path.join(dir, `page-${n}.jpg`), "jpeg");
    }
  }
  const icons = path.join(root, "public/icons");
  await shot(iconHtml(192, false), path.join(icons, "icon-192.png"), "png");
  await shot(iconHtml(512, false), path.join(icons, "icon-512.png"), "png");
  await shot(iconHtml(512, true), path.join(icons, "icon-maskable-512.png"), "png");
  await shot(iconHtml(180, true), path.join(icons, "apple-touch-icon.png"), "png");
  await browser.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
