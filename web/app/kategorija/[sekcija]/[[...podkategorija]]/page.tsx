import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { PopisStranica } from '@/components/PopisStranica';
import { APP_NAME, imaBazu } from '@/lib/config';
import { PODKATEGORIJE, SEKCIJE, podkategorija, sekcija } from '@/lib/kategorije';
import { traziOglase } from '@/lib/oglasi';
import { brojStranice, filteriIzUpita } from '@/lib/pretraga';
import { jsonLdPutanja, jsonUScript } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 60;
type SP = Promise<Record<string, string | string[] | undefined>>;
type P = Promise<{ sekcija: string; podkategorija?: string[] }>;

export function generateStaticParams() {
  return [
    ...SEKCIJE.map((s) => ({ sekcija: s.slug, podkategorija: [] as string[] })),
    ...PODKATEGORIJE.map((p) => ({ sekcija: p.sekcija, podkategorija: [p.slug] })),
  ];
}

async function razrijesi(params: P) {
  const { sekcija: ss, podkategorija: ps } = await params;
  const sek = sekcija(ss);
  if (!sek || (ps?.length ?? 0) > 1) return null;
  const pod = ps?.length ? podkategorija(ps[0]) : undefined;
  if (ps?.length && (!pod || pod.sekcija !== sek.slug)) return null;
  return { sek, pod };
}

export async function generateMetadata({ params, searchParams }: { params: P; searchParams: SP }): Promise<Metadata> {
  const r = await razrijesi(params);
  if (!r) return {};
  const sp = await searchParams;
  const f = filteriIzUpita(sp);
  const s = brojStranice(sp);
  const filtrirano = !!(f.q || f.cijenaOd != null || f.cijenaDo != null || f.drzava || f.zupanija || f.grad || f.stanje || Object.keys(f.polja ?? {}).length || f.sort !== 'najnovije');
  const naziv = r.pod?.naziv ?? r.sek.naziv;
  const put = `/kategorija/${r.sek.slug}${r.pod ? `/${r.pod.slug}` : ''}`;
  return {
    title: `${naziv}: oglasi`,
    description: `${naziv} na ${APP_NAME}: pregledaj oglase i kontaktiraj prodavatelje izravno.`,
    alternates: { canonical: s > 1 ? `${put}?stranica=${s}` : put },
    robots: filtrirano ? { index: false, follow: true } : undefined,
  };
}

export default async function KategorijaStranica({ params, searchParams }: { params: P; searchParams: SP }) {
  const r = await razrijesi(params);
  if (!r) notFound();
  const sp = await searchParams;
  const f = filteriIzUpita(sp, r.pod?.slug);
  if (!r.pod) f.sekcija = r.sek.slug;
  const stranica = brojStranice(sp);
  const rezultat = await traziOglase(javniKlijent(), f, stranica);
  const naziv = r.pod?.naziv ?? r.sek.naziv;
  const put = `/kategorija/${r.sek.slug}${r.pod ? `/${r.pod.slug}` : ''}`;
  const mrvice = [{ naziv: 'Početna', put: '/' }, { naziv: 'Kategorije', put: '/kategorije' }, { naziv: r.sek.naziv, put: `/kategorija/${r.sek.slug}` }, ...(r.pod ? [{ naziv: r.pod.naziv, put }] : [])];
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript(jsonLdPutanja(mrvice)) }} />
      <PopisStranica naslov={naziv} natrag={`/kategorije?s=${r.sek.slug}`} osnova={put} filteri={f} stranica={stranica} rezultat={rezultat} kategorijaSlug={r.pod?.slug} sekcijaSlug={r.sek.slug} bazaSpojena={imaBazu()} />
    </>
  );
}
