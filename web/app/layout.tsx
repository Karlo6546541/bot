import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import Link from 'next/link';
import { APP_NAME, APP_SLOGAN, SITE_URL } from '@/lib/config';
import { jsonLdStranica, jsonUScript } from '@/lib/seo';
import { KorisnikVeze } from '@/components/KorisnikVeze';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: `${APP_NAME} – ${APP_SLOGAN}`, template: `%s | ${APP_NAME}` },
  description: `${APP_NAME}: ${APP_SLOGAN.toLowerCase()}. Kartice, kovanice, marke, stripovi, figurice i gramofonske ploče iz cijele regije.`,
  openGraph: { type: 'website', siteName: APP_NAME, locale: 'hr_HR' },
  alternates: { canonical: '/' },
};

export const viewport: Viewport = { width: 'device-width', initialScale: 1, themeColor: '#1f6f7a' };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="hr">
      <body>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript(jsonLdStranica()) }} />
        <a className="sr-only" href="#sadrzaj">Preskoči na sadržaj</a>
        <header className="zaglavlje">
          <div className="zaglavlje-unutra">
            <Link className="logo" href="/" aria-label={`${APP_NAME} – početna`}>
              <b>{APP_NAME}</b>
              <small>{APP_SLOGAN}</small>
            </Link>
            <Link className="ikona-gumb" href="/oglasi" aria-label="Pretraži oglase" title="Pretraži">🔍</Link>
            <KorisnikVeze />
            <Link className="gumb glavni malen objavi-zaglavlje" href="/objavi">+ Objavi oglas</Link>
          </div>
        </header>
        <main id="sadrzaj">{children}</main>
        <footer className="podnozje">
          <div className="podnozje-unutra">
            <span>© {new Date().getFullYear()} {APP_NAME}</span>
            <Link href="/uvjeti">Uvjeti korištenja</Link>
            <Link href="/privatnost">Privatnost</Link>
            <Link href="/kontakt">Kontakt</Link>
          </div>
        </footer>
        <Link className="gumb glavni objavi-plutajuci" href="/objavi">+ Objavi oglas</Link>
      </body>
    </html>
  );
}
