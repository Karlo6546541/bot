import Link from 'next/link';
import type { OglasKartica } from '@/lib/oglasi';
import { IK } from '@/lib/ikone';
import { podkategorija } from '@/lib/kategorije';
import { lokacijaTekst } from '@/lib/lokacije';
import { putOglasa } from '@/lib/seo';
import { cijenaTekst } from '@/lib/tekst';
import { Ikona } from './Ikona';
import { KatAvatar } from './KatArt';

/** Pločica oglasa kao u aplikaciji: kvadratna slika, oznaka kategorije, naziv, cijena, stanje. */
export function OglasKarticaVeza({ oglas, prioritet = false }: { oglas: OglasKartica; prioritet?: boolean }) {
  const kat = podkategorija(oglas.kategorija);
  const slika = oglas.slike_male[0];
  return (
    <Link className="plocica" href={putOglasa(oglas)} data-mjesto={lokacijaTekst(oglas, false)}>
      <div className="slika">
        {slika ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={slika} alt={oglas.naslov} width={240} height={240} loading={prioritet ? 'eager' : 'lazy'} decoding="async" />
        ) : (
          <KatAvatar ikona={kat?.ikona ?? IK.sellOutlined} boja={kat?.boja ?? 0} />
        )}
        <span className="pilula-kat">
          <Ikona k={IK.sellOutlined} />
          <span className="t">{oglas.status === 'prodano' ? 'Prodano' : (kat?.jednina ?? 'Oglas')}</span>
        </span>
      </div>
      <div className="info">
        <h3 className="ime">{oglas.naslov}</h3>
        <div className="mala">Cijena</div>
        <div className="cijena">{cijenaTekst(oglas.cijena)}</div>
        <div className="mala">{oglas.stanje}</div>
      </div>
    </Link>
  );
}

export function MrezaOglasa({ oglasi }: { oglasi: OglasKartica[] }) {
  return (
    <div className="plocice">
      {oglasi.map((o, i) => (
        <OglasKarticaVeza key={o.id} oglas={o} prioritet={i < 4} />
      ))}
    </div>
  );
}
