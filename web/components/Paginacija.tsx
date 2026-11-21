import Link from 'next/link';

export function Paginacija({ stranica, ukupnoStranica, adresa }: { stranica: number; ukupnoStranica: number; adresa: (s: number) => string }) {
  if (ukupnoStranica <= 1) return null;
  return (
    <nav className="paginacija" aria-label="Stranice">
      {stranica > 1 && <Link href={adresa(stranica - 1)} rel="prev">‹ Prethodna</Link>}
      <span className="trenutna" aria-current="page">{stranica} / {ukupnoStranica}</span>
      {stranica < ukupnoStranica && <Link href={adresa(stranica + 1)} rel="next">Sljedeća ›</Link>}
    </nav>
  );
}
