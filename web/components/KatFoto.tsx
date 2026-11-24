import { KatIlustracija } from './KatIlustracija';

/** Pločica kategorije: vlastita ilustracija na podlozi boje kategorije. */
export function KatFoto({ slug, boja, alt }: { slug: string; boja: number; alt: string }) {
  return (
    <span className={`kat-foto c${boja}`}>
      <KatIlustracija slug={slug} naslov={alt} />
    </span>
  );
}
