import type { Metadata } from 'next';
import { PopisStranica } from '@/components/PopisStranica';
import { imaBazu } from '@/lib/config';
import { traziOglase } from '@/lib/oglasi';
import { brojStranice, filteriIzUpita } from '@/lib/pretraga';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 60;
type SP = Promise<Record<string, string | string[] | undefined>>;

export async function generateMetadata({ searchParams }: { searchParams: SP }): Promise<Metadata> {
  const sp = await searchParams;
  const f = filteriIzUpita(sp);
  const filtrirano = !!(f.q || f.kategorija || f.cijenaOd != null || f.cijenaDo != null || f.drzava || f.zupanija || f.grad || f.stanje || Object.keys(f.polja ?? {}).length || f.sort !== 'najnovije');
  const s = brojStranice(sp);
  return {
    title: f.q ? `Pretraga: ${f.q}` : 'Svi oglasi',
    description: 'Oglasi za kolekcionare: kartice, kovanice, marke, stripovi, figurice i ploče. Filtriraj po državi, županiji, gradu i cijeni.',
    alternates: { canonical: s > 1 ? `/oglasi?stranica=${s}` : '/oglasi' },
    // Filtrirane inačice ne ulaze u indeks (izbjegava duplirani sadržaj), ali se poveznice prate.
    robots: filtrirano ? { index: false, follow: true } : undefined,
  };
}

export default async function OglasiStranica({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const f = filteriIzUpita(sp);
  const stranica = brojStranice(sp);
  const rezultat = await traziOglase(javniKlijent(), f, stranica);
  return <PopisStranica naslov={f.q ? `Pretraga: ${f.q}` : 'Oglasi'} osnova="/oglasi" filteri={f} stranica={stranica} rezultat={rezultat} bazaSpojena={imaBazu()} />;
}
