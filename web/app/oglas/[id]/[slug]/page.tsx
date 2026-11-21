import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound, permanentRedirect } from 'next/navigation';
import { Fragment } from 'react';
import { MrezaOglasa } from '@/components/Kartice';
import { Galerija } from '@/components/Galerija';
import { OglasAkcije } from '@/components/OglasAkcije';
import { SigurnaKupnja } from '@/components/SigurnaKupnja';
import { APP_NAME } from '@/lib/config';
import { podkategorija, poljaKategorije, sekcija } from '@/lib/kategorije';
import { IK } from '@/lib/ikone';
import { Ikona } from '@/components/Ikona';
import { Traka } from '@/components/Traka';
import { lokacijaTekst } from '@/lib/lokacije';
import { brojAktivnih, dohvatiOglas, dohvatiProfil, slicniOglasi } from '@/lib/oglasi';
import { jeIstekao } from '@/lib/pretraga';
import { jsonLdOglas, jsonLdPutanja, jsonUScript, opisOglasa, putOglasa } from '@/lib/seo';
import { javniKlijent } from '@/lib/supabase';
import { cijenaTekst, datum, prije } from '@/lib/tekst';

export const revalidate = 60;
type P = Promise<{ id: string; slug: string }>;

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const { id } = await params;
  const o = await dohvatiOglas(javniKlijent(), id);
  if (!o) return { title: 'Oglas nije pronađen', robots: { index: false } };
  const put = putOglasa(o);
  const aktivan = o.status === 'aktivan' && !jeIstekao(o);
  return {
    title: `${o.naslov} – ${cijenaTekst(o.cijena)}`,
    description: opisOglasa(o),
    alternates: { canonical: put },
    // Prodani i istekli oglasi ostaju dostupni, ali ne ulaze u indeks.
    robots: aktivan ? undefined : { index: false, follow: true },
    openGraph: { type: 'website', title: o.naslov, description: opisOglasa(o), url: put, images: o.slike.slice(0, 1).map((url) => ({ url })) },
    twitter: { card: 'summary_large_image' },
  };
}

export default async function OglasStranica({ params }: { params: P }) {
  const { id, slug } = await params;
  const sb = javniKlijent();
  const o = await dohvatiOglas(sb, id);
  if (!o || o.status === 'obrisan') notFound();
  // Stari ili pogrešan slug vodi na kanonsku adresu (trajno preusmjeravanje).
  if (slug !== putOglasa(o).split('/').pop()) permanentRedirect(putOglasa(o));
  const kat = podkategorija(o.kategorija);
  const sek = sekcija(kat?.sekcija);
  const putKat = sek && kat ? `/kategorija/${sek.slug}/${kat.slug}` : '/oglasi';
  const [prodavatelj, broj, slicni] = await Promise.all([dohvatiProfil(sb, o.korisnik_id), brojAktivnih(sb, o.korisnik_id), slicniOglasi(sb, o)]);
  const nedostupan = o.status !== 'aktivan' || jeIstekao(o);
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonUScript(jsonLdOglas(o)) }} />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonUScript(jsonLdPutanja([{ naziv: 'Početna', put: '/' }, { naziv: kat?.naziv ?? 'Oglasi', put: putKat }, { naziv: o.naslov, put: putOglasa(o) }])),
        }}
      />
      <Traka natrag={putKat} h1={false}>
        <a className="ikona-gumb" href="#kontakt" aria-label="Spremi oglas"><Ikona k={IK.favoriteBorder} /></a>
      </Traka>
      <div className="detalj">
        <div className="detalj-mreza">
          <Galerija naslov={o.naslov} slike={o.slike} male={o.slike_male} />
          <div>
            <h1>{o.naslov}</h1>
            <div className="velika-cijena">{cijenaTekst(o.cijena)}</div>
            <div className="sitno">{kat?.jednina ?? 'Oglas'} · {o.stanje}</div>
            {nedostupan && (
              <p style={{ marginTop: 10 }}>
                <span className={`oznaka ${o.status === 'prodano' ? '' : 'siva'}`}>{o.status === 'prodano' ? 'Prodano' : o.status === 'uklonjen' ? 'Uklonjen' : 'Istekao'}</span>{' '}
                {o.status === 'prodano' ? 'Ovaj predmet je prodan.' : o.status === 'uklonjen' ? 'Oglas je uklonio moderator.' : 'Oglas je istekao.'}
              </p>
            )}
            <hr className="razdjelnik" />
            <h2>Opis</h2>
            <p className="opis">{o.opis}</p>
            <hr className="razdjelnik" />
            <dl className="svojstva">
              <dt>Stanje</dt>
              <dd>{o.stanje}</dd>
              {poljaKategorije(o.kategorija).map((p) =>
                o.polja[p.kljuc] ? (
                  <Fragment key={p.kljuc}>
                    <dt>{p.naziv}</dt>
                    <dd>{o.polja[p.kljuc]}</dd>
                  </Fragment>
                ) : null,
              )}
              <dt>Lokacija</dt>
              <dd>{lokacijaTekst(o)}</dd>
              <dt>Objavljeno</dt>
              <dd>
                <time dateTime={o.objavljeno}>{datum(o.objavljeno)}</time> ({prije(o.objavljeno)})
              </dd>
            </dl>
            <SigurnaKupnja />
            {prodavatelj && (
              <div className="prodavatelj">
                <Link className="profil" href={`/korisnik/${prodavatelj.id}`}>
                  <span className="avatar">{prodavatelj.ime.slice(0, 1).toUpperCase()}</span>
                  <span style={{ minWidth: 0 }}>
                    <span className="ime" style={{ display: 'block' }}>{prodavatelj.ime}</span>
                    <span className="pomoc">Član od {datum(prodavatelj.registriran)} · {broj} {broj === 1 ? 'aktivan oglas' : 'aktivnih oglasa'}</span>
                  </span>
                </Link>
              </div>
            )}
            <OglasAkcije oglas={{ id: o.id, naslov: o.naslov, korisnik_id: o.korisnik_id, status: o.status, prikazi_telefon: o.prikazi_telefon, cijena: o.cijena, nedostupan }} />
          </div>
        </div>
      </div>
      {!nedostupan && (
        <div className="donja-traka">
          <div>
            <a className="gumb glavni sirok nizak" href="#kontakt">Kontaktiraj prodavatelja</a>
          </div>
        </div>
      )}
      {slicni.length > 0 && (
        <section aria-label="Slični oglasi" style={{ marginTop: 28, paddingBottom: 80 }}>
          <h2 className="naslov-odjeljka" style={{ padding: '0 16px' }}>Slični oglasi: {kat?.naziv}</h2>
          <MrezaOglasa oglasi={slicni} />
        </section>
      )}
      <p className="pomoc" style={{ padding: '0 16px 96px' }}>{APP_NAME} je oglasnik: cijenu, plaćanje i preuzimanje dogovarate izravno s prodavateljem.</p>
    </>
  );
}
