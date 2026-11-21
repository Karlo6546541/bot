import type { MetadataRoute } from 'next';
import { SITE_URL } from '@/lib/config';
import { KATEGORIJE } from '@/lib/kategorije';
import { oglasiZaSitemap } from '@/lib/oglasi';
import { putOglasa } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const oglasi = await oglasiZaSitemap(javniKlijent(3600));
  return [
    { url: `${SITE_URL}/`, changeFrequency: 'daily', priority: 1 },
    { url: `${SITE_URL}/oglasi`, changeFrequency: 'hourly', priority: 0.9 },
    ...KATEGORIJE.map((k) => ({ url: `${SITE_URL}/kategorija/${k.slug}`, changeFrequency: 'hourly' as const, priority: 0.8 })),
    ...oglasi.map((o) => ({
      url: `${SITE_URL}${putOglasa(o)}`,
      lastModified: o.azurirano ?? o.objavljeno,
      changeFrequency: 'weekly' as const,
      priority: 0.6,
    })),
    { url: `${SITE_URL}/uvjeti`, priority: 0.1 },
    { url: `${SITE_URL}/privatnost`, priority: 0.1 },
    { url: `${SITE_URL}/kontakt`, priority: 0.1 },
  ];
}
