import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { notFound } from 'next/navigation';
import { APP_NAME, SITE_URL } from '@/lib/config';
import { JEZICI, OG_LOCALE, alternative, jezik, prevedi } from '@/lib/i18n';
import { jsonLdStranica, jsonUScript } from '@/lib/seo';
import { JezikProvider } from '@/components/Jezik';
import { Ljuska } from '@/components/Ljuska';
import '../globals.css';

type P = Promise<{ lang: string }>;
export const generateStaticParams = () => JEZICI.map((lang) => ({ lang }));

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const j = jezik((await params).lang);
  const slogan = prevedi(j, 'Oglasnik za kolekcionare');
  return {
    metadataBase: new URL(SITE_URL),
    title: { default: `${APP_NAME} – ${slogan}`, template: `%s | ${APP_NAME}` },
    description: prevedi(j, '{app}: oglasnik za kolekcionare. Kartice, kovanice, marke, stripovi, figure i gramofonske ploče iz cijele regije.', { app: APP_NAME }),
    openGraph: { type: 'website', siteName: APP_NAME, locale: OG_LOCALE[j], alternateLocale: j === 'hr' ? 'en_GB' : 'hr_HR' },
    twitter: { card: 'summary_large_image' },
    alternates: alternative(j, '/'),
  };
}

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  colorScheme: 'light dark',
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#171c1d' },
    { media: '(prefers-color-scheme: light)', color: '#f3f6f6' },
  ],
};

export default async function RootLayout({ children, params }: { children: ReactNode; params: P }) {
  const { lang } = await params;
  if (!JEZICI.includes(lang as never)) notFound();
  const j = jezik(lang);
  return (
    <html lang={j}>
      <head>
        <link rel="preload" href="/fonts/mi.woff2" as="font" type="font/woff2" crossOrigin="anonymous" />
        <link rel="preload" href="/fonts/inter-400.woff2" as="font" type="font/woff2" crossOrigin="anonymous" />
        <link rel="preconnect" href="https://mwhrjrxytfdttjjdhdns.supabase.co" crossOrigin="anonymous" />
      </head>
      <body>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript(jsonLdStranica(j)) }} />
        <a className="sr-only" href="#sadrzaj">{prevedi(j, 'Preskoči na sadržaj')}</a>
        <JezikProvider jezik={j}>
          <Ljuska>
            <main id="sadrzaj" className="sredina">{children}</main>
          </Ljuska>
        </JezikProvider>
      </body>
    </html>
  );
}
