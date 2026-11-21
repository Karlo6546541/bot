import Link from 'next/link';
import type { OglasKartica } from '@/lib/oglasi';
import { lokacijaTekst } from '@/lib/lokacije';
import { putOglasa } from '@/lib/seo';
import { cijenaTekst, prije } from '@/lib/tekst';

export function OglasKarticaVeza({ oglas, prioritet = false }: { oglas: OglasKartica; prioritet?: boolean }) {
  return (
    <article className="kartica">
      <Link className="sadrzaj" href={putOglasa(oglas)}>
        <div className="slika">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={oglas.slike_male[0]}
            alt={oglas.naslov}
            width={240}
            height={240}
            loading={prioritet ? 'eager' : 'lazy'}
            decoding="async"
          />
        </div>
        <div className="tekst">
          <h3 className="naslov">{oglas.naslov}</h3>
          <div className="cijena">{cijenaTekst(oglas.cijena)}</div>
          <div className="mjesto">{lokacijaTekst(oglas, false)} · {prije(oglas.objavljeno)}</div>
        </div>
      </Link>
      {oglas.status === 'prodano' && <span className="oznaka oznaka-na-slici">Prodano</span>}
    </article>
  );
}

export function MrezaOglasa({ oglasi }: { oglasi: OglasKartica[] }) {
  return (
    <div className="mreza">
      {oglasi.map((o, i) => (
        <OglasKarticaVeza key={o.id} oglas={o} prioritet={i < 4} />
      ))}
    </div>
  );
}
