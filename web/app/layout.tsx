import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { APP_NAME, APP_SLOGAN, SITE_URL } from '@/lib/config';
import { jsonLdStranica, jsonUScript } from '@/lib/seo';
import { Ljuska } from '@/components/Ljuska';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: `${APP_NAME} – ${APP_SLOGAN}`, template: `%s | ${APP_NAME}` },
  description: `${APP_NAME}: ${APP_SLOGAN.toLowerCase()}. Kartice, kovanice, marke, stripovi, figure i gramofonske ploče iz cijele regije.`,
  openGraph: { type: 'website', siteName: APP_NAME, locale: 'hr_HR' },
  alternates: { canonical: '/' },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#171c1d' },
    { media: '(prefers-color-scheme: light)', color: '#f3f6f6' },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="hr">
      <head>
        <link rel="preload" href="/fonts/mi.woff2" as="font" type="font/woff2" crossOrigin="anonymous" />
        <link rel="preload" href="/fonts/inter-400.woff2" as="font" type="font/woff2" crossOrigin="anonymous" />
      </head>
      <body>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript(jsonLdStranica()) }} />
        <a className="sr-only" href="#sadrzaj">Preskoči na sadržaj</a>
        <Ljuska>
          <main id="sadrzaj" className="sredina">{children}</main>
        </Ljuska>
      </body>
    </html>
  );
}
