import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { Slika } from '@/components/Slika';
import { StatusOznaka } from '@/components/StatusOznaka';
import { Traka } from '@/components/Traka';
import { VlasnikAkcije } from '@/components/VlasnikAkcije';
import { IK } from '@/lib/ikone';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { lokacijaTekst } from '@/lib/lokacije';
import { mojiOglasi } from '@/lib/oglasi';
import { jeAktivan, jeIstekao } from '@/lib/pretraga';
import { putOglasa } from '@/lib/seo';
import { klijentServera } from '@/lib/supabase';
import { cijenaTekst, danaDoIsteka, datum } from '@/lib/tekst';
import type { Oglas } from '@/lib/types';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Moji oglasi'), robots: { index: false } };
}
const TABOVI: { k: string; naziv: string; uvjet: (o: Oglas) => boolean }[] = [
  { k: 'aktivni', naziv: 'Aktivni', uvjet: (o) => jeAktivan(o) },
  { k: 'istekli', naziv: 'Istekli', uvjet: (o) => jeIstekao(o) },
  { k: 'prodani', naziv: 'Prodani', uvjet: (o) => o.status === 'prodano' },
  { k: 'uklonjeni', naziv: 'Uklonjeni', uvjet: (o) => o.status === 'uklonjen' },
];

export default async function MojiOglasi({ params, searchParams }: { params: P; searchParams: Promise<Record<string, string | undefined>> }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, '/moji-oglasi')}`);
  const svi = await mojiOglasi(sb, data.user.id);
  const trazeni = (await searchParams).tab;
  const tab = TABOVI.find((x) => x.k === trazeni) ?? TABOVI[0];
  const popis = svi.filter(tab.uvjet);
  return (
    <>
      <Traka naslov={t('Moji oglasi')} natrag="/profil">
        <Link className="ikona-gumb" href={put(j, '/objavi')} aria-label={t('Novi oglas')}><Ikona k={IK.addCircleOutline} /></Link>
      </Traka>
      <nav className="tabovi-linija" aria-label={t('Status oglasa')}>
        {TABOVI.map((x) => (
          <Link key={x.k} href={`${put(j, '/moji-oglasi')}?tab=${x.k}`} aria-current={x.k === tab.k ? 'page' : undefined}>
            {t(x.naziv)} ({svi.filter(x.uvjet).length})
          </Link>
        ))}
      </nav>
      {popis.length === 0 && (
        <div className="prazno">
          <div className="krug"><Ikona k={IK.sellOutlined} /></div>
          <b>{tab.k === 'aktivni' ? t('Nemaš aktivnih oglasa') : t('Ovdje još nema oglasa')}</b>
          {tab.k === 'aktivni' && <Link className="gumb glavni" href={put(j, '/objavi')}>{t('Objavi oglas')}</Link>}
        </div>
      )}
      {popis.map((o) => (
        <div className="redak" key={o.id} data-moj-oglas={o.id}>
          <Link className="slicica" href={put(j, putOglasa(o))} style={{ position: 'relative' }}><Slika src={o.slike_male[0]} alt="" sizes="56px" /></Link>
          <div className="tijelo stog">
            <div>
              <Link className="naslov" href={put(j, putOglasa(o))}>{o.naslov}</Link>
              <div><b>{cijenaTekst(o.cijena, j)}</b> · <StatusOznaka oglas={o} jezik={j} /></div>
              <div className="pomoc">
                {lokacijaTekst(o, true, j)} ·{' '}
                {jeAktivan(o) ? t('istječe za {n} dana', { n: danaDoIsteka(o.istjece) })
                  : o.status === 'prodano' ? `${t('prodano')} ${o.prodano_datum ? datum(o.prodano_datum, j) : ''}${o.prodano_cijena != null ? ` · ${cijenaTekst(o.prodano_cijena, j)}` : ''}`
                  : o.status === 'uklonjen' ? `${t('uklonio moderator')}${o.uklonjeno_razlog ? `: ${t(o.uklonjeno_razlog)}` : ''}`
                  : t('istekao {d}', { d: datum(o.istjece, j) })}
              </div>
            </div>
            <VlasnikAkcije oglasId={o.id} status={o.status} istekao={jeIstekao(o)} cijena={o.cijena} />
          </div>
        </div>
      ))}
    </>
  );
}
