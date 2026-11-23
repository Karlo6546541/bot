import type { MetadataRoute } from 'next';
import { SITE_URL } from '@/lib/config';

const PRIVATNO = ['/poruke', '/admin', '/profil', '/moji-oglasi', '/favoriti', '/objavi', '/prijava', '/registracija', '/trazi'];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: '*', allow: '/', disallow: [...PRIVATNO, ...PRIVATNO.map((p) => `/en${p}`), '/auth/', '/api/', '/*/uredi'] }],
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
