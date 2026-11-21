import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { StatusOznaka } from '@/components/StatusOznaka';
import { VlasnikAkcije } from '@/components/VlasnikAkcije';
import { lokacijaTekst } from '@/lib/lokacije';
import { mojiOglasi } from '@/lib/oglasi';
import { jeAktivan, jeIstekao } from '@/lib/pretraga';
import { putOglasa } from '@/lib/seo';
import { klijentServera } from '@/lib/supabase';
import { cijenaTekst, danaDoIsteka, datum } from '@/lib/tekst';
import type { Oglas } from '@/lib/types';

export const metadata: Metadata = { title: 'Moji oglasi', robots: { index: false } };
const TABOVI: { k: string; naziv: string; uvjet: (o: Oglas) => boolean }[] = [
  { k: 'aktivni', naziv: 'Aktivni', uvjet: (o) => jeAktivan(o) },
  { k: 'istekli', naziv: 'Istekli', uvjet: (o) => jeIstekao(o) },
  { k: 'prodani', naziv: 'Prodani', uvjet: (o) => o.status === 'prodano' },
  { k: 'uklonjeni', naziv: 'Uklonjeni', uvjet: (o) => o.status === 'uklonjen' },
];

export default async function MojiOglasi({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect('/prijava?natrag=/moji-oglasi');
  const svi = await mojiOglasi(sb, data.user.id);
  const trazeni = (await searchParams).tab;
  const tab = TABOVI.find((t) => t.k === trazeni) ?? TABOVI[0];
  const popis = svi.filter(tab.uvjet);
  return (
    <>
      <div className="odjeljak-naslov">
        <h1>Moji oglasi</h1>
        <Link className="gumb glavni malen" href="/objavi">+ Novi oglas</Link>
      </div>
      <nav className="kartice-tabovi" aria-label="Status oglasa">
        {TABOVI.map((t) => (
          <Link key={t.k} href={`/moji-oglasi?tab=${t.k}`} aria-current={t.k === tab.k ? 'page' : undefined}
            style={{ padding: '6px 14px', borderRadius: 99, border: '1px solid var(--line)', background: t.k === tab.k ? 'var(--brand)' : 'var(--surface)', color: t.k === tab.k ? 'var(--brand-ink)' : 'var(--ink)', fontWeight: 600, textDecoration: 'none', whiteSpace: 'nowrap' }}>
            {t.naziv} ({svi.filter(t.uvjet).length})
          </Link>
        ))}
      </nav>
      {popis.length === 0 && <div className="prazno ploca">{tab.k === 'aktivni' ? 'Nemaš aktivnih oglasa.' : 'Ovdje još nema oglasa.'}</div>}
      {popis.map((o) => (
        <div className="redak" key={o.id} data-moj-oglas={o.id}>
          <Link className="slicica" href={putOglasa(o)}>{/* eslint-disable-next-line @next/next/no-img-element */}<img src={o.slike_male[0]} alt="" loading="lazy" /></Link>
          <div className="tijelo stog">
            <div>
              <Link className="naslov" href={putOglasa(o)}>{o.naslov}</Link>
              <div><b>{cijenaTekst(o.cijena)}</b> · <StatusOznaka oglas={o} /></div>
              <div className="pomoc">
                {lokacijaTekst(o)} ·{' '}
                {jeAktivan(o) ? `istječe za ${danaDoIsteka(o.istjece)} dana`
                  : o.status === 'prodano' ? `prodano ${o.prodano_datum ? datum(o.prodano_datum) : ''}${o.prodano_cijena != null ? ` za ${cijenaTekst(o.prodano_cijena)}` : ''}`
                  : o.status === 'uklonjen' ? `uklonio moderator${o.uklonjeno_razlog ? `: ${o.uklonjeno_razlog}` : ''}`
                  : `istekao ${datum(o.istjece)}`}
              </div>
            </div>
            <VlasnikAkcije oglasId={o.id} status={o.status} istekao={jeIstekao(o)} cijena={o.cijena} />
          </div>
        </div>
      ))}
    </>
  );
}
