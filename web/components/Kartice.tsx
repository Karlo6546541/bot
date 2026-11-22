import Link from 'next/link';
import type { OglasKartica } from '@/lib/oglasi';
import { IK } from '@/lib/ikone';
import { prevedi, put, type Jezik } from '@/lib/i18n';
import { jedninaNa, podkategorija } from '@/lib/kategorije';
import { lokacijaTekst } from '@/lib/lokacije';
import { putOglasa } from '@/lib/seo';
import { cijenaTekst } from '@/lib/tekst';
import { Ikona } from './Ikona';
import { KatAvatar } from './KatArt';
import { Slika } from './Slika';

/** Pločica oglasa kao u aplikaciji: kvadratna slika, oznaka kategorije, naziv, cijena, stanje. */
export function OglasKarticaVeza({ oglas, prioritet = false, jezik = 'hr' }: { oglas: OglasKartica; prioritet?: boolean; jezik?: Jezik }) {
  const kat = podkategorija(oglas.kategorija);
  const slika = oglas.slike_male[0];
  return (
    <Link className="plocica" href={put(jezik, putOglasa(oglas))} data-mjesto={lokacijaTekst(oglas, false)}>
      <div className="slika">
        {slika ? (
          <Slika src={slika} alt={oglas.naslov} sizes="(min-width: 900px) 260px, (min-width: 600px) 30vw, 46vw" prioritet={prioritet} />
        ) : (
          <KatAvatar ikona={kat?.ikona ?? IK.sellOutlined} boja={kat?.boja ?? 0} />
        )}
        <span className="pilula-kat">
          <Ikona k={IK.sellOutlined} />
          <span className="t">{oglas.status === 'prodano' ? prevedi(jezik, 'Prodano') : kat ? jedninaNa(kat, jezik) : prevedi(jezik, 'Oglas')}</span>
        </span>
      </div>
      <div className="info">
        <h3 className="ime">{oglas.naslov}</h3>
        <div className="mala">{prevedi(jezik, 'Cijena')}</div>
        <div className="cijena">{cijenaTekst(oglas.cijena, jezik)}</div>
        <div className="mala">{prevedi(jezik, oglas.stanje)}</div>
      </div>
    </Link>
  );
}

export function MrezaOglasa({ oglasi, jezik = 'hr' }: { oglasi: OglasKartica[]; jezik?: Jezik }) {
  return (
    <div className="plocice">
      {oglasi.map((o, i) => (
        <OglasKarticaVeza key={o.id} oglas={o} prioritet={i < 4} jezik={jezik} />
      ))}
    </div>
  );
}
