import type { MetadataRoute } from 'next';
import { SITE_URL } from '@/lib/config';
import { put } from '@/lib/i18n';
import { PODKATEGORIJE, SEKCIJE } from '@/lib/kategorije';
import { oglasiZaSitemap } from '@/lib/oglasi';
import { putOglasa } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 3600;

type Unos = MetadataRoute.Sitemap[number];
/** Hrvatska adresa s engleskom inačicom (hreflang). */
function unos(p: string, x: Omit<Unos, 'url'> = {}): Unos[] {
  const languages = { hr: `${SITE_URL}${p === '/' ? '' : p}`, en: `${SITE_URL}${put('en', p)}` };
  return [
    { url: languages.hr || SITE_URL, alternates: { languages }, ...x },
    { url: languages.en, alternates: { languages }, ...x, priority: x.priority != null ? Math.max(0.1, x.priority - 0.1) : undefined },
  ];
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  let oglasi: Awaited<ReturnType<typeof oglasiZaSitemap>> = [];
  try {
    oglasi = await oglasiZaSitemap(javniKlijent(3600));
  } catch (e) {
    console.error('Sitemap:', (e as Error).message);
  }
  return [
    ...unos('/', { changeFrequency: 'daily', priority: 1 }),
    ...unos('/oglasi', { changeFrequency: 'hourly', priority: 0.9 }),
    ...unos('/kategorije', { changeFrequency: 'weekly', priority: 0.7 }),
    ...SEKCIJE.flatMap((k) => unos(`/kategorija/${k.slug}`, { changeFrequency: 'hourly', priority: 0.8 })),
    ...PODKATEGORIJE.flatMap((k) => unos(`/kategorija/${k.sekcija}/${k.slug}`, { changeFrequency: 'hourly', priority: 0.7 })),
    ...oglasi.flatMap((o) => unos(putOglasa(o), { lastModified: o.azurirano ?? o.objavljeno, changeFrequency: 'weekly', priority: 0.6, images: (o.slike ?? []).slice(0, 3) })),
    ...unos('/uvjeti', { priority: 0.1 }),
    ...unos('/privatnost', { priority: 0.1 }),
    ...unos('/kontakt', { priority: 0.1 }),
  ];
}
