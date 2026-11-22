import { Ikona } from './Ikona';
import { Slika } from './Slika';

/** Fotografija kategorije (iz stvarnog oglasa) ili, dok oglasa nema, ikona na mekoj obojenoj podlozi. */
export function KatFoto({ slika, ikona, boja, alt, prioritet = false }: { slika?: string; ikona: number; boja: number; alt: string; prioritet?: boolean }) {
  return (
    <span className={`kat-foto c${boja}`}>
      {slika ? <Slika src={slika} alt={alt} sizes="(min-width: 700px) 140px, 30vw" prioritet={prioritet} /> : <Ikona k={ikona} />}
    </span>
  );
}
