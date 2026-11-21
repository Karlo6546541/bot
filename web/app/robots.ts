import type { MetadataRoute } from 'next';
import { SITE_URL } from '@/lib/config';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: '*', allow: '/', disallow: ['/poruke', '/admin', '/profil', '/moji-oglasi', '/favoriti', '/objavi', '/prijava', '/registracija', '/auth/'] }],
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
