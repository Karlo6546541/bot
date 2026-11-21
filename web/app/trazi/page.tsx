import type { Metadata } from 'next';
import Link from 'next/link';
import { Ikona } from '@/components/Ikona';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { PODKATEGORIJE, SEKCIJE } from '@/lib/kategorije';

export const metadata: Metadata = { title: 'Pretraga', robots: { index: false, follow: true } };
const POPULARNE = ['pokemon-i-ostali-tcg', 'kovanice', 'markice', 'vinil', 'stripovi-i-manga', 'konzole', 'rucni-satovi', 'figure-i-funko'];

export default async function Trazi({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const kategorije = sp.tab === 'kategorije';
  return (
    <>
      <div className="trazi-traka">
        <Link className="ikona-gumb" href="/" aria-label="Natrag"><Ikona k={IK.back} /></Link>
        <form action={kategorije ? '/kategorije' : '/oglasi'} method="get" role="search">
          <div className="trazi-polje">
            <label className="sr-only" htmlFor="q">{kategorije ? 'Traži kategoriju' : 'Pretraži oglase'}</label>
            <input id="q" type="search" name="q" defaultValue={sp.q ?? ''} placeholder={kategorije ? 'Traži kategoriju' : 'Pretraži oglase'} enterKeyHint="search" autoFocus />
            <Ikona k={IK.search} />
          </div>
        </form>
      </div>
      <h1 className="sr-only">Pretraga oglasa</h1>
      <h2 className="lista-zaglavlje">Popularne kategorije</h2>
      <nav className="cipovi" aria-label="Popularne kategorije" style={{ flexWrap: 'wrap', overflow: 'visible' }}>
        {POPULARNE.map((s) => {
          const p = PODKATEGORIJE.find((x) => x.slug === s)!;
          return <Link key={s} className="cip" href={`/kategorija/${p.sekcija}/${p.slug}`}>{p.naziv}</Link>;
        })}
      </nav>
      <h2 className="lista-zaglavlje">Sve kategorije</h2>
      {SEKCIJE.map((s) => (
        <Link key={s.slug} className="lista-red" href={`/kategorija/${s.slug}`}>
          <Ikona k={s.ikona} />
          <span className="t">{s.naziv}</span>
          <Ikona k={IK.chevronRight} />
        </Link>
      ))}
    </>
  );
}
