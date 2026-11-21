import Link from 'next/link';
import { MrezaOglasa } from '@/components/Kartice';
import { APP_SLOGAN, imaBazu } from '@/lib/config';
import { KATEGORIJE } from '@/lib/kategorije';
import { DRZAVE } from '@/lib/lokacije';
import { traziOglase } from '@/lib/oglasi';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 120;

export default async function Pocetna() {
  const najnoviji = await traziOglase(javniKlijent(120), { sort: 'najnovije' }, 1, 12);
  return (
    <>
      <section className="uvod">
        <h1>{APP_SLOGAN}</h1>
        <p className="pomoc">Objavi oglas besplatno, pronađi ono što skupljaš i dogovori se izravno s prodavateljem.</p>
        <form className="pretraga-velika" role="search" action="/oglasi" method="get">
          <label className="sr-only" htmlFor="trazi">Pretraži oglase</label>
          <input id="trazi" type="search" name="q" placeholder="Što tražiš? npr. Charizard, kovanica 1 kuna…" enterKeyHint="search" />
          <button className="gumb glavni" type="submit">Traži</button>
        </form>
      </section>
      <h2>Kategorije</h2>
      <nav className="kategorije" aria-label="Kategorije">
        {KATEGORIJE.map((k) => (
          <Link key={k.slug} className="kategorija-plocica" href={`/kategorija/${k.slug}`}>
            <span aria-hidden="true">{k.ikona}</span>
            <span>{k.naziv}</span>
          </Link>
        ))}
      </nav>
      <div className="odjeljak-naslov">
        <h2>Najnoviji oglasi</h2>
        <Link href="/oglasi">Svi oglasi ›</Link>
      </div>
      {!imaBazu() && <div className="greska">Baza oglasa trenutno nije spojena.</div>}
      {najnoviji.stavke.length === 0 ? (
        <div className="prazno ploca">
          <p>Još nema oglasa. Budi prvi!</p>
          <Link className="gumb glavni" href="/objavi">Objavi oglas</Link>
        </div>
      ) : (
        <MrezaOglasa oglasi={najnoviji.stavke} />
      )}
      <h2 style={{ marginTop: 24 }}>Oglasi po državi</h2>
      <div className="sitni-popis">
        {DRZAVE.filter((d) => d.kod !== 'XX').map((d) => (
          <Link key={d.kod} href={`/oglasi?drzava=${d.kod}`}>{d.naziv}</Link>
        ))}
      </div>
    </>
  );
}
