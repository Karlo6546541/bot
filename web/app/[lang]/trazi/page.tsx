import type { Metadata } from 'next';
import Link from 'next/link';
import { Ikona } from '@/components/Ikona';
import { PametnaPretraga } from '@/components/PametnaPretraga';
import { IK } from '@/lib/ikone';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { PODKATEGORIJE, SEKCIJE, nazivNa } from '@/lib/kategorije';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Pretraga'), robots: { index: false, follow: true } };
}
const POPULARNE = ['pokemon-i-ostali-tcg', 'kovanice', 'markice', 'vinil', 'stripovi-i-manga', 'konzole', 'rucni-satovi', 'figure-i-funko'];

export default async function Trazi({ params, searchParams }: { params: P; searchParams: Promise<Record<string, string | undefined>> }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  const sp = await searchParams;
  return (
    <PametnaPretraga pocetni={sp.q ?? ''}>
      <h2 className="lista-zaglavlje">{t('Popularne kategorije')}</h2>
      <nav className="cipovi" aria-label={t('Popularne kategorije')} style={{ flexWrap: 'wrap', overflow: 'visible' }}>
        {POPULARNE.map((s) => {
          const p = PODKATEGORIJE.find((x) => x.slug === s)!;
          return <Link key={s} className="cip" href={put(j, `/kategorija/${p.sekcija}/${p.slug}`)}>{nazivNa(p, j)}</Link>;
        })}
      </nav>
      <h2 className="lista-zaglavlje">{t('Sve kategorije')}</h2>
      {SEKCIJE.map((s) => (
        <Link key={s.slug} className="lista-red" href={put(j, `/kategorija/${s.slug}`)}>
          <Ikona k={s.ikona} />
          <span className="t">{nazivNa(s, j)}</span>
          <Ikona k={IK.chevronRight} />
        </Link>
      ))}
    </PametnaPretraga>
  );
}
