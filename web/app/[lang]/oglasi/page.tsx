import type { Metadata } from 'next';
import { PopisStranica } from '@/components/PopisStranica';
import { imaBazu } from '@/lib/config';
import { jezik, prevedi, put } from '@/lib/i18n';
import { traziOglase } from '@/lib/oglasi';
import { brojStranice, filteriIzUpita } from '@/lib/pretraga';
import { javniKlijent } from '@/lib/supabase';

type SP = Promise<Record<string, string | string[] | undefined>>;
type P = Promise<{ lang: string }>;

export async function generateMetadata({ params, searchParams }: { params: P; searchParams: SP }): Promise<Metadata> {
  const j = jezik((await params).lang);
  const sp = await searchParams;
  const f = filteriIzUpita(sp);
  const filtrirano = !!(f.q || f.kategorija || f.cijenaOd != null || f.cijenaDo != null || f.drzava || f.zupanija || f.grad || f.stanje || Object.keys(f.polja ?? {}).length || f.sort !== 'najnovije');
  const s = brojStranice(sp);
  const osnova = s > 1 ? `/oglasi?stranica=${s}` : '/oglasi';
  return {
    title: f.q ? prevedi(j, 'Pretraga: {q}', { q: f.q }) : prevedi(j, 'Svi oglasi'),
    description: prevedi(j, 'Oglasi za kolekcionare: kartice, kovanice, marke, stripovi, figurice i ploče. Filtriraj po državi, županiji, gradu i cijeni.'),
    alternates: { canonical: put(j, osnova), languages: { hr: osnova, en: put('en', osnova), 'x-default': osnova } },
    // Filtrirane inačice ne ulaze u indeks (izbjegava duplirani sadržaj), ali se poveznice prate.
    robots: filtrirano ? { index: false, follow: true } : undefined,
  };
}

export default async function OglasiStranica({ params, searchParams }: { params: P; searchParams: SP }) {
  const j = jezik((await params).lang);
  const sp = await searchParams;
  const f = filteriIzUpita(sp);
  const stranica = brojStranice(sp);
  let greska = false;
  let rezultat: Awaited<ReturnType<typeof traziOglase>> = { stavke: [], ukupno: 0 };
  try {
    rezultat = await traziOglase(javniKlijent(), f, stranica);
  } catch (e) {
    greska = true;
    console.error('Oglasi:', (e as Error).message);
  }
  return <PopisStranica jezik={j} naslov={f.q ? prevedi(j, 'Pretraga: {q}', { q: f.q }) : prevedi(j, 'Oglasi')} osnova="/oglasi" filteri={f} stranica={stranica} rezultat={rezultat} bazaSpojena={imaBazu()} greska={greska} />;
}
