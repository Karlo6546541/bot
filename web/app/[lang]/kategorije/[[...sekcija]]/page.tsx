import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { KatFoto } from '@/components/KatFoto';
import { IK } from '@/lib/ikone';
import { JEZICI, alternative, jezik, prevodilac, put } from '@/lib/i18n';
import { SEKCIJE, nazivNa, sekcija } from '@/lib/kategorije';
import { pregledKategorija } from '@/lib/oglasi';
import { javniKlijent } from '@/lib/supabase';

export const revalidate = 600;
export const dynamicParams = false;
type P = Promise<{ lang: string; sekcija?: string[] }>;

export function generateStaticParams() {
  return JEZICI.flatMap((lang) => [{ lang, sekcija: [] }, ...SEKCIJE.map((s) => ({ lang, sekcija: [s.slug] }))]);
}

async function odabrana(params: P) {
  const p = await params;
  const s = p.sekcija?.length ? sekcija(p.sekcija[0]) : SEKCIJE[0];
  return { j: jezik(p.lang), s, prazno: !p.sekcija?.length };
}

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const { j, s, prazno } = await odabrana(params);
  if (!s) return {};
  const t = prevodilac(j);
  return {
    title: prazno ? t('Kategorije') : nazivNa(s, j),
    description: t('Sve kategorije oglasa za kolekcionare: kartice, novci, markice, stripovi, figure, ploče, satovi i više.'),
    alternates: alternative(j, prazno ? '/kategorije' : `/kategorije/${s.slug}`),
  };
}

export default async function Kategorije({ params }: { params: P }) {
  const { j, s: odabranaS } = await odabrana(params);
  if (!odabranaS) notFound();
  const t = prevodilac(j);
  let pregled: Awaited<ReturnType<typeof pregledKategorija>> = {};
  try {
    pregled = await pregledKategorija(javniKlijent(600));
  } catch (e) {
    console.error('Kategorije:', (e as Error).message);
  }
  return (
    <>
      <div style={{ padding: '16px 16px 8px' }}>
        <Link className="pilula-trazi" href={put(j, '/trazi')}>
          <Ikona k={IK.search} />
          <span>{t('Pretraži oglase')}</span>
        </Link>
      </div>
      <h1 className="sr-only">{t('Kategorije oglasa')}</h1>
      <div className="kat-raspored">
        <nav className="kat-tracnica" aria-label={t('Glavne kategorije')}>
          {SEKCIJE.map((s) => (
            <Link key={s.slug} href={put(j, `/kategorije/${s.slug}`)} aria-current={s.slug === odabranaS.slug ? 'true' : undefined} scroll={false}>
              <Ikona k={s.ikona} />
              {nazivNa(s, j)}
            </Link>
          ))}
        </nav>
        <section className="kat-desno" aria-label={nazivNa(odabranaS, j)}>
          <div className="kat-glava">
            <h2>{nazivNa(odabranaS, j)}</h2>
            <Link href={put(j, `/kategorija/${odabranaS.slug}`)}>{t('Sve')}</Link>
          </div>
          <div className="kat-mreza">
            {odabranaS.podkategorije.map((p, i) => {
              const broj = pregled[p.slug]?.broj ?? 0;
              return (
                <Link key={p.slug} className="kat-foto-veza" href={put(j, `/kategorija/${odabranaS.slug}/${p.slug}`)}>
                  <KatFoto slika={pregled[p.slug]?.slika} ikona={p.ikona} boja={p.boja} alt={nazivNa(p, j)} prioritet={i < 6} />
                  <b>{nazivNa(p, j)}</b>
                  <small>{broj === 0 ? t('Još nema oglasa') : t(broj === 1 ? '{n} oglas' : '{n} oglasa', { n: broj })}</small>
                </Link>
              );
            })}
          </div>
        </section>
      </div>
    </>
  );
}
