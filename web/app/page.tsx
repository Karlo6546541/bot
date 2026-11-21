import Link from 'next/link';
import { MrezaOglasa } from '@/components/Kartice';
import { Ikona } from '@/components/Ikona';
import { PravneVeze } from '@/components/PravneVeze';
import { APP_SLOGAN, imaBazu } from '@/lib/config';
import { IK } from '@/lib/ikone';
import { DRZAVE } from '@/lib/lokacije';
import { traziOglase } from '@/lib/oglasi';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 120;

export default async function Pocetna() {
  // Privremeni problem s bazom ne smije srušiti izgradnju ni početnu stranicu.
  let najnoviji: Awaited<ReturnType<typeof traziOglase>> = { stavke: [], ukupno: 0 };
  let nedostupno = false;
  try {
    najnoviji = await traziOglase(javniKlijent(120), { sort: 'najnovije' }, 1, 12);
  } catch (e) {
    nedostupno = true;
    console.error('Početna: oglasi se ne mogu učitati:', (e as Error).message);
  }
  return (
    <>
      <h1 className="sr-only">{APP_SLOGAN}</h1>
      <div style={{ padding: '16px 16px 0' }}>
        <Link className="pilula-trazi" href="/trazi" role="search" aria-label="Pretraži oglase">
          <Ikona k={IK.search} />
          <span>Pretraži oglase</span>
        </Link>
      </div>
      <h2 className="naslov-odjeljka" style={{ padding: '24px 16px 0' }}>Najnoviji oglasi</h2>
      {!imaBazu() && <div className="greska" style={{ margin: 16 }}>Baza oglasa trenutno nije spojena.</div>}
      {nedostupno && <div className="greska" style={{ margin: 16 }}>Oglasi se trenutno ne mogu učitati. Pokušaj ponovno za nekoliko minuta.</div>}
      {najnoviji.stavke.length === 0 ? (
        <div className="prazno">
          <div className="krug"><Ikona k={IK.sellOutlined} /></div>
          <b>Još nema oglasa</b>
          <p>Budi prvi i objavi oglas besplatno.</p>
          <Link className="gumb glavni" href="/objavi">Objavi oglas</Link>
        </div>
      ) : (
        <MrezaOglasa oglasi={najnoviji.stavke} />
      )}
      <nav className="sitni-popis" aria-label="Oglasi po državi" style={{ paddingBottom: 8 }}>
        {DRZAVE.filter((d) => d.kod !== 'XX').map((d) => (
          <Link key={d.kod} className="cip" href={`/oglasi?drzava=${d.kod}`}>{d.naziv}</Link>
        ))}
      </nav>
      <PravneVeze />
    </>
  );
}
