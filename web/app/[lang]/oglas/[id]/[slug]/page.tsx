import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound, permanentRedirect } from 'next/navigation';
import { Fragment } from 'react';
import { MrezaOglasa } from '@/components/Kartice';
import { Galerija } from '@/components/Galerija';
import { OglasAkcije } from '@/components/OglasAkcije';
import { SigurnaKupnja } from '@/components/SigurnaKupnja';
import { Traka } from '@/components/Traka';
import { APP_NAME } from '@/lib/config';
import { jezik, prevodilac, put } from '@/lib/i18n';
import { jedninaNa, nazivNa, podkategorija, poljaKategorije, sekcija } from '@/lib/kategorije';
import { lokacijaTekst } from '@/lib/lokacije';
import { brojAktivnih, dohvatiOglas, dohvatiProfil, slicniOglasi } from '@/lib/oglasi';
import { jeIstekao } from '@/lib/pretraga';
import { jsonLdOglas, jsonLdPutanja, jsonUScript, opisOglasa, putOglasa } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';
import { cijenaTekst, datum } from '@/lib/tekst';

// Stranica oglasa se kešira (ISR) i osvježava najviše svakih 60 s: prvi posjet je jedini spori.
export const revalidate = 60;
export const generateStaticParams = async () => [];
type P = Promise<{ lang: string; id: string; slug: string }>;

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const { id, lang } = await params;
  const j = jezik(lang);
  const t = prevodilac(j);
  const o = await dohvatiOglas(javniKlijent(), id);
  if (!o) return { title: t('Oglas nije pronađen'), robots: { index: false } };
  const p = putOglasa(o);
  const aktivan = o.status === 'aktivan' && !jeIstekao(o);
  return {
    title: `${o.naslov} – ${cijenaTekst(o.cijena, j)}`,
    description: opisOglasa(o, j),
    alternates: { canonical: put(j, p), languages: { hr: p, en: put('en', p), 'x-default': p } },
    // Prodani i istekli oglasi ostaju dostupni, ali ne ulaze u indeks.
    robots: aktivan ? undefined : { index: false, follow: true },
    openGraph: { type: 'website', title: o.naslov, description: opisOglasa(o, j), url: put(j, p), images: o.slike.slice(0, 1).map((url) => ({ url })) },
    twitter: { card: 'summary_large_image' },
  };
}

export default async function OglasStranica({ params }: { params: P }) {
  const { id, slug, lang } = await params;
  const j = jezik(lang);
  const t = prevodilac(j);
  const sb = javniKlijent();
  const o = await dohvatiOglas(sb, id);
  if (!o || o.status === 'obrisan') notFound();
  // Stari ili pogrešan slug vodi na kanonsku adresu (trajno preusmjeravanje).
  if (slug !== putOglasa(o).split('/').pop()) permanentRedirect(put(j, putOglasa(o)));
  const kat = podkategorija(o.kategorija);
  const sek = sekcija(kat?.sekcija);
  const putKat = sek && kat ? `/kategorija/${sek.slug}/${kat.slug}` : '/oglasi';
  const [prodavatelj, broj, slicni] = await Promise.all([dohvatiProfil(sb, o.korisnik_id), brojAktivnih(sb, o.korisnik_id), slicniOglasi(sb, o)]);
  const nedostupan = o.status !== 'aktivan' || jeIstekao(o);
  const status = o.status === 'prodano' ? t('Prodano') : o.status === 'uklonjen' ? t('Uklonjen') : t('Istekao');
  const statusOpis = o.status === 'prodano' ? t('Ovaj predmet je prodan.') : o.status === 'uklonjen' ? t('Oglas je uklonio moderator.') : t('Oglas je istekao.');
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript(jsonLdOglas(o, j)) }} />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonUScript(jsonLdPutanja([{ naziv: t('Početna'), put: put(j, '/') }, { naziv: kat ? nazivNa(kat, j) : t('Oglasi'), put: put(j, putKat) }, { naziv: o.naslov, put: put(j, putOglasa(o)) }])),
        }}
      />
      <Traka natrag={putKat} naslov={kat ? nazivNa(kat, j) : undefined} h1={false} />
      <div className="detalj">
        <div className="detalj-mreza">
          <Galerija naslov={o.naslov} slike={o.slike} male={o.slike_male} />
          <div>
            <h1>{o.naslov}</h1>
            <div className="velika-cijena">{cijenaTekst(o.cijena, j)}</div>
            <div className="sitno">{kat ? jedninaNa(kat, j) : t('Oglas')} · {t(o.stanje)} · {lokacijaTekst(o, false)}</div>
            {nedostupan && (
              <p style={{ marginTop: 10 }}>
                <span className={`oznaka ${o.status === 'prodano' ? '' : 'siva'}`}>{status}</span> {statusOpis}
              </p>
            )}
            <hr className="razdjelnik" />
            <h2>{t('Opis')}</h2>
            <p className="opis">{o.opis}</p>
            <hr className="razdjelnik" />
            <dl className="svojstva">
              <dt>{t('Stanje')}</dt>
              <dd>{t(o.stanje)}</dd>
              {poljaKategorije(o.kategorija).map((p) =>
                o.polja[p.kljuc] ? (
                  <Fragment key={p.kljuc}>
                    <dt>{t(p.naziv)}</dt>
                    <dd>{t(o.polja[p.kljuc])}</dd>
                  </Fragment>
                ) : null,
              )}
              <dt>{t('Lokacija')}</dt>
              <dd>{lokacijaTekst(o, true, j)}</dd>
              <dt>{t('Objavljeno')}</dt>
              <dd>
                <time dateTime={o.objavljeno}>{datum(o.objavljeno, j)}</time>
              </dd>
            </dl>
            <SigurnaKupnja />
            {prodavatelj && (
              <div className="prodavatelj">
                <Link className="profil" href={put(j, `/korisnik/${prodavatelj.id}`)}>
                  <span className="avatar">{prodavatelj.ime.slice(0, 1).toUpperCase()}</span>
                  <span style={{ minWidth: 0 }}>
                    <span className="ime" style={{ display: 'block' }}>{prodavatelj.ime}</span>
                    <span className="pomoc">{t('Član od {d}', { d: datum(prodavatelj.registriran, j) })} · {t(broj === 1 ? '{n} aktivan oglas' : '{n} aktivnih oglasa', { n: broj })}</span>
                  </span>
                </Link>
              </div>
            )}
            <OglasAkcije oglas={{ id: o.id, naslov: o.naslov, korisnik_id: o.korisnik_id, status: o.status, prikazi_telefon: o.prikazi_telefon, cijena: o.cijena, nedostupan }} />
          </div>
        </div>
      </div>
      {slicni.length > 0 && (
        <section aria-label={t('Slični oglasi')} style={{ marginTop: 28 }}>
          <h2 className="naslov-odjeljka" style={{ padding: '0 16px' }}>{t('Slični oglasi')}</h2>
          <MrezaOglasa oglasi={slicni} jezik={j} />
        </section>
      )}
      <p className="pomoc" style={{ padding: '0 16px 96px' }}>{t('{app} je oglasnik: cijenu, plaćanje i preuzimanje dogovarate izravno s prodavateljem.', { app: APP_NAME })}</p>
      {!nedostupan && (
        <div className="donja-traka">
          <div>
            <a className="gumb glavni sirok nizak" href="#kontakt">{t('Kontaktiraj prodavatelja')}</a>
          </div>
        </div>
      )}
    </>
  );
}
