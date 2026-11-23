import { KatIlustracija } from './KatIlustracija';

/** Krug s emojijem i sjajem u boji kategorije (kao CategoryArt u aplikaciji). */
export function KatArt({ emoji, boja, velicina = 44 }: { emoji: string; boja: number; velicina?: number }) {
  return (
    <i className={`kat-art c${boja}`} style={{ width: velicina, height: velicina, fontSize: velicina * 0.62 }} aria-hidden="true">
      {emoji}
    </i>
  );
}

/** Rezervna slika oglasa bez fotografije: ikona kategorije u obojenom okviru. */
export function KatAvatar({ slug, boja }: { slug?: string; boja: number }) {
  return (
    <span className={`kat-avatar c${boja}`} aria-hidden="true">
      <KatIlustracija slug={slug ?? ''} />
    </span>
  );
}
