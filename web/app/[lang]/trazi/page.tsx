import type { Metadata } from 'next';
import Link from 'next/link';
import { Ikona } from '@/components/Ikona';
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
    <>
      <div className="trazi-traka">
        <Link className="ikona-gumb" href={put(j, '/')} aria-label={t('Natrag')}><Ikona k={IK.back} /></Link>
        <form action={put(j, '/oglasi')} method="get" role="search">
          <div className="trazi-polje">
            <label className="sr-only" htmlFor="q">{t('Pretraži oglase')}</label>
            <input id="q" type="search" name="q" defaultValue={sp.q ?? ''} placeholder={t('Pretraži oglase')} enterKeyHint="search" autoFocus autoComplete="off" />
            <button type="submit" className="ikona-gumb" aria-label={t('Traži')} style={{ width: 40, height: 40 }}><Ikona k={IK.search} /></button>
          </div>
        </form>
      </div>
      <h1 className="sr-only">{t('Pretraga oglasa')}</h1>
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
    </>
  );
}
