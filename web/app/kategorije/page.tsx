import type { Metadata } from 'next';
import Link from 'next/link';
import { Ikona } from '@/components/Ikona';
import { KatArt } from '@/components/KatArt';
import { IK } from '@/lib/ikone';
import { SEKCIJE, sekcija } from '@/lib/kategorije';

export const metadata: Metadata = {
  title: 'Kategorije',
  description: 'Sve kategorije oglasa za kolekcionare: kartice, novci, markice, stripovi, figure, ploče, satovi i više.',
  alternates: { canonical: '/kategorije' },
};

export default async function Kategorije({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const odabrana = sekcija((await searchParams).s) ?? SEKCIJE[0];
  return (
    <>
      <div style={{ padding: '16px 16px 8px' }}>
        <Link className="pilula-trazi" href="/trazi?tab=kategorije">
          <Ikona k={IK.search} />
          <span>Traži kategoriju</span>
        </Link>
      </div>
      <h1 className="sr-only">Kategorije oglasa</h1>
      <div className="kat-raspored">
        <nav className="kat-tracnica" aria-label="Glavne kategorije">
          {SEKCIJE.map((s) => (
            <Link key={s.slug} href={`/kategorije?s=${s.slug}`} aria-current={s.slug === odabrana.slug ? 'true' : undefined} scroll={false}>
              <Ikona k={s.ikona} />
              {s.naziv}
            </Link>
          ))}
        </nav>
        <section className="kat-desno" aria-label={odabrana.naziv}>
          <div className="kat-glava">
            <h2>{odabrana.naziv}</h2>
            <Link href={`/kategorija/${odabrana.slug}`}>Sve</Link>
          </div>
          <div className="kat-mreza">
            {odabrana.podkategorije.map((p) => (
              <Link key={p.slug} href={`/kategorija/${odabrana.slug}/${p.slug}`}>
                <KatArt emoji={p.emoji} boja={p.boja} />
                <b>{p.naziv}</b>
              </Link>
            ))}
          </div>
        </section>
      </div>
    </>
  );
}
