import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { PopisStranica } from '@/components/PopisStranica';
import { APP_NAME, imaBazu } from '@/lib/config';
import { KATEGORIJE, kategorija } from '@/lib/kategorije';
import { traziOglase } from '@/lib/oglasi';
import { brojStranice, filteriIzUpita } from '@/lib/pretraga';
import { jsonLdPutanja, jsonUScript } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 60;
type SP = Promise<Record<string, string | string[] | undefined>>;
type P = Promise<{ slug: string }>;

export function generateStaticParams() {
  return KATEGORIJE.map((k) => ({ slug: k.slug }));
}

export async function generateMetadata({ params, searchParams }: { params: P; searchParams: SP }): Promise<Metadata> {
  const { slug } = await params;
  const kat = kategorija(slug);
  if (!kat) return {};
  const sp = await searchParams;
  const f = filteriIzUpita(sp, slug);
  const s = brojStranice(sp);
  const filtrirano = !!(f.q || f.cijenaOd != null || f.cijenaDo != null || f.drzava || f.zupanija || f.grad || f.stanje || Object.keys(f.polja ?? {}).length || f.sort !== 'najnovije');
  return {
    title: `${kat.naziv}: oglasi`,
    description: `${kat.naziv} na ${APP_NAME}: ${kat.opis.toLowerCase()}. Pregledaj oglase i kontaktiraj prodavatelje.`,
    alternates: { canonical: s > 1 ? `/kategorija/${slug}?stranica=${s}` : `/kategorija/${slug}` },
    robots: filtrirano ? { index: false, follow: true } : undefined,
  };
}

export default async function KategorijaStranica({ params, searchParams }: { params: P; searchParams: SP }) {
  const { slug } = await params;
  const kat = kategorija(slug);
  if (!kat) notFound();
  const sp = await searchParams;
  const f = filteriIzUpita(sp, slug);
  const stranica = brojStranice(sp);
  const rezultat = await traziOglase(javniKlijent(), f, stranica);
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonUScript(jsonLdPutanja([{ naziv: 'Početna', put: '/' }, { naziv: 'Oglasi', put: '/oglasi' }, { naziv: kat.naziv, put: `/kategorija/${slug}` }])),
        }}
      />
      <PopisStranica naslov={kat.naziv} osnova={`/kategorija/${slug}`} filteri={f} stranica={stranica} rezultat={rezultat} kategorijaSlug={slug} bazaSpojena={imaBazu()} />
    </>
  );
}
