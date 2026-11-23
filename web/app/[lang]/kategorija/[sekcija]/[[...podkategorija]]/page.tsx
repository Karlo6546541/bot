import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { PopisStranica } from '@/components/PopisStranica';
import { APP_NAME, imaBazu } from '@/lib/config';
import { jezik, prevedi, put, type Jezik } from '@/lib/i18n';
import { nazivNa, podkategorija, sekcija } from '@/lib/kategorije';
import { traziOglase } from '@/lib/oglasi';
import { brojStranice, filteriIzUpita } from '@/lib/pretraga';
import { jsonLdPopis, jsonLdPutanja, jsonUScript } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';

type SP = Promise<Record<string, string | string[] | undefined>>;
type P = Promise<{ lang: string; sekcija: string; podkategorija?: string[] }>;

async function razrijesi(params: P) {
  const { lang, sekcija: ss, podkategorija: ps } = await params;
  const j: Jezik = jezik(lang);
  const sek = sekcija(ss);
  if (!sek || (ps?.length ?? 0) > 1) return null;
  const pod = ps?.length ? podkategorija(ps[0]) : undefined;
  if (ps?.length && (!pod || pod.sekcija !== sek.slug)) return null;
  const osnova = `/kategorija/${sek.slug}${pod ? `/${pod.slug}` : ''}`;
  return { j, sek, pod, osnova, naziv: pod ? nazivNa(pod, j) : nazivNa(sek, j) };
}

export async function generateMetadata({ params, searchParams }: { params: P; searchParams: SP }): Promise<Metadata> {
  const r = await razrijesi(params);
  if (!r) return {};
  const sp = await searchParams;
  const f = filteriIzUpita(sp);
  const s = brojStranice(sp);
  const filtrirano = !!(f.q || f.cijenaOd != null || f.cijenaDo != null || f.drzava || f.zupanija || f.grad || f.stanje || Object.keys(f.polja ?? {}).length || f.sort !== 'najnovije');
  const p = s > 1 ? `${r.osnova}?stranica=${s}` : r.osnova;
  return {
    title: prevedi(r.j, '{kat}: oglasi', { kat: r.naziv }),
    description: prevedi(r.j, '{kat} na {app}: pregledaj oglase i kontaktiraj prodavatelje izravno.', { kat: r.naziv, app: APP_NAME }),
    alternates: { canonical: put(r.j, p), languages: { hr: p, en: put('en', p), 'x-default': p } },
    robots: filtrirano ? { index: false, follow: true } : undefined,
  };
}

export default async function KategorijaStranica({ params, searchParams }: { params: P; searchParams: SP }) {
  const r = await razrijesi(params);
  if (!r) notFound();
  const { j, sek, pod } = r;
  const sp = await searchParams;
  const f = filteriIzUpita(sp, pod?.slug);
  if (!pod) f.sekcija = sek.slug;
  const stranica = brojStranice(sp);
  let greska = false;
  let rezultat: Awaited<ReturnType<typeof traziOglase>> = { stavke: [], ukupno: 0 };
  try {
    rezultat = await traziOglase(javniKlijent(), f, stranica);
  } catch (e) {
    greska = true;
    console.error('Kategorija:', (e as Error).message);
  }
  const mrvice = [
    { naziv: prevedi(j, 'Početna'), put: put(j, '/') },
    { naziv: prevedi(j, 'Kategorije'), put: put(j, '/kategorije') },
    { naziv: nazivNa(sek, j), put: put(j, `/kategorija/${sek.slug}`) },
    ...(pod ? [{ naziv: nazivNa(pod, j), put: put(j, r.osnova) }] : []),
  ];
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript([jsonLdPutanja(mrvice), ...(rezultat.stavke.length ? [jsonLdPopis(rezultat.stavke, j)] : [])]) }} />
      <PopisStranica jezik={j} naslov={r.naziv} natrag={`/kategorije/${sek.slug}`} osnova={r.osnova} filteri={f} stranica={stranica} rezultat={rezultat}
        kategorijaSlug={pod?.slug} sekcijaSlug={sek.slug} bazaSpojena={imaBazu()} greska={greska} />
    </>
  );
}
