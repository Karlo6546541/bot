import Link from 'next/link';
import { MrezaOglasa } from '@/components/Kartice';
import { Ikona } from '@/components/Ikona';
import { KatFoto } from '@/components/KatFoto';
import { PravneVeze } from '@/components/PravneVeze';
import { imaBazu } from '@/lib/config';
import { IK } from '@/lib/ikone';
import { jezik, prevodilac, put } from '@/lib/i18n';
import { PODKATEGORIJE, nazivNa } from '@/lib/kategorije';
import { DRZAVE, nazivDrzave } from '@/lib/lokacije';
import { pregledKategorija, traziOglase } from '@/lib/oglasi';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 60;
type P = Promise<{ lang: string }>;

export default async function Pocetna({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  // Privremeni problem s bazom ne smije srušiti izgradnju ni početnu stranicu.
  let najnoviji: Awaited<ReturnType<typeof traziOglase>> = { stavke: [], ukupno: 0 };
  let pregled: Awaited<ReturnType<typeof pregledKategorija>> = {};
  let nedostupno = false;
  try {
    [najnoviji, pregled] = await Promise.all([traziOglase(javniKlijent(120), { sort: 'najnovije' }, 1, 12), pregledKategorija(javniKlijent(600))]);
  } catch (e) {
    nedostupno = true;
    console.error('Početna: oglasi se ne mogu učitati:', (e as Error).message);
  }
  // Najpopunjenije kategorije s fotografijom.
  const popularne = PODKATEGORIJE
    .sort((a, b) => (pregled[b.slug]?.broj ?? 0) - (pregled[a.slug]?.broj ?? 0))
    .slice(0, 10);
  return (
    <>
      <h1 className="sr-only">{t('Oglasnik za kolekcionare')}</h1>
      <div style={{ padding: '16px 16px 0' }}>
        <Link className="pilula-trazi" href={put(j, '/trazi')} role="search" aria-label={t('Pretraži oglase')}>
          <Ikona k={IK.search} />
          <span>{t('Pretraži oglase')}</span>
        </Link>
      </div>
      {popularne.length > 0 && (
        <>
          <div className="odjeljak-glava">
            <h2 className="naslov-odjeljka">{t('Kategorije')}</h2>
            <Link href={put(j, '/kategorije')}>{t('Sve')}</Link>
          </div>
          <nav className="kat-traka" aria-label={t('Kategorije')}>
            {popularne.map((p) => (
              <Link key={p.slug} href={put(j, `/kategorija/${p.sekcija}/${p.slug}`)} className="kat-foto-veza">
                <KatFoto slug={p.slug} boja={p.boja} alt={nazivNa(p, j)} />
                <b>{nazivNa(p, j)}</b>
              </Link>
            ))}
          </nav>
        </>
      )}
      <h2 className="naslov-odjeljka" style={{ padding: '20px 16px 0' }}>{t('Najnoviji oglasi')}</h2>
      {!imaBazu() && <div className="greska" style={{ margin: 16 }}>{t('Baza oglasa trenutno nije spojena.')}</div>}
      {nedostupno && <div className="greska" style={{ margin: 16 }}>{t('Oglasi se trenutno ne mogu učitati. Pokušaj ponovno za nekoliko minuta.')}</div>}
      {najnoviji.stavke.length === 0 ? (
        <div className="prazno">
          <div className="krug"><Ikona k={IK.sellOutlined} /></div>
          <b>{t('Još nema oglasa')}</b>
          <p>{t('Budi prvi i objavi oglas besplatno.')}</p>
          <Link className="gumb glavni" href={put(j, '/objavi')}>{t('Objavi oglas')}</Link>
        </div>
      ) : (
        <>
          <MrezaOglasa oglasi={najnoviji.stavke} jezik={j} />
          <div style={{ display: 'flex', justifyContent: 'center', padding: '0 16px 16px' }}>
            <Link className="gumb" href={put(j, '/oglasi')}>{t('Svi oglasi')}</Link>
          </div>
        </>
      )}
      <nav className="sitni-popis" aria-label={t('Oglasi po državi')} style={{ paddingBottom: 8 }}>
        {DRZAVE.filter((d) => d.kod !== 'XX').map((d) => (
          <Link key={d.kod} className="cip" href={put(j, `/oglasi?drzava=${d.kod}`)}>{nazivDrzave(d.kod, j)}</Link>
        ))}
      </nav>
      <PravneVeze />
    </>
  );
}
