import Link from 'next/link';
import { prevedi, type Jezik } from '@/lib/i18n';

export function Paginacija({ stranica, ukupnoStranica, adresa, jezik = 'hr' }: { stranica: number; ukupnoStranica: number; adresa: (s: number) => string; jezik?: Jezik }) {
  if (ukupnoStranica <= 1) return null;
  return (
    <nav className="paginacija" aria-label={prevedi(jezik, 'Stranice')}>
      {stranica > 1 && <Link href={adresa(stranica - 1)} rel="prev">‹ {prevedi(jezik, 'Prethodna')}</Link>}
      <span className="trenutna" aria-current="page">{stranica} / {ukupnoStranica}</span>
      {stranica < ukupnoStranica && <Link href={adresa(stranica + 1)} rel="next">{prevedi(jezik, 'Sljedeća')} ›</Link>}
    </nav>
  );
}
