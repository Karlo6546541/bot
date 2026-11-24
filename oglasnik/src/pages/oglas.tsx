import { Fragment } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { RAZLOZI_PRIJAVE, kategorija, type RazlogPrijave } from '../config/kategorije';
import { backend } from '../data';
import type { Oglas } from '../data/types';
import { jeAktivan, jeIstekao } from '../lib/pretraga';
import { adresa, idi } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { obavijest, useJa, useUcitaj } from '../lib/stanje';
import { cijenaTekst, datum, prije } from '../lib/tekst';
import { Dijalog, Greska, SigurnaKupnja, StatusOznaka, Ucitavanje, putOglasa, useFavoriti } from '../components/ui';
import { UpravljanjeOglasom } from './moji';

function Galerija({ oglas }: { oglas: Oglas }) {
  const [i, setI] = useState(0);
  return (
    <div class="galerija">
      <div class="glavna">
        <img src={oglas.slike[i]} alt={`${oglas.naslov} – fotografija ${i + 1}`} decoding="async" />
      </div>
      {oglas.slike.length > 1 && (
        <div class="male" role="list">
          {oglas.slike_male.map((s, j) => (
            <button
              key={s}
              type="button"
              role="listitem"
              aria-current={i === j}
              aria-label={`Fotografija ${j + 1}`}
              onClick={() => setI(j)}
            >
              <img src={s} alt="" loading="lazy" />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Prodavatelj({ oglas }: { oglas: Oglas }) {
  const p = useUcitaj(async () => {
    const [profil, broj] = await Promise.all([
      backend.profil(oglas.korisnik_id),
      backend.brojAktivnihOglasa(oglas.korisnik_id),
    ]);
    return { profil, broj };
  }, [oglas.korisnik_id]);
  if (!p.podaci?.profil) return null;
  const { profil, broj } = p.podaci;
  return (
    <div class="ploca">
      <div class="pomoc">Prodavatelj</div>
      <a href={adresa(`/korisnik/${profil.id}`)} style={{ fontWeight: 700, fontSize: '1.1rem' }}>
        {profil.ime}
      </a>
      <div class="pomoc">
        Član od {datum(profil.registriran)} · {broj} {broj === 1 ? 'aktivan oglas' : 'aktivnih oglasa'}
      </div>
    </div>
  );
}

function Kontakt({ oglas }: { oglas: Oglas }) {
  const { ja } = useJa();
  const [tekst, setTekst] = useState(`Pozdrav, zanima me "${oglas.naslov}". Je li još dostupno?`);
  const [salje, setSalje] = useState(false);
  const [greska, setGreska] = useState('');
  const [telefon, setTelefon] = useState<string | null | undefined>(undefined);
  const postojeci = useUcitaj(() => (ja ? backend.postojeciRazgovor(oglas.id) : Promise.resolve(null)), [ja?.id, oglas.id]);
  const natrag = `/prijava?natrag=${encodeURIComponent(putOglasa(oglas))}`;

  if (!jeAktivan(oglas)) return null;
  if (!ja) {
    return (
      <div class="ploca stog">
        <a class="gumb glavni sirok" href={adresa(natrag)}>
          Kontaktiraj prodavatelja
        </a>
        <p class="pomoc">Za slanje poruke prijavi se ili napravi račun.</p>
      </div>
    );
  }
  if (ja.id === oglas.korisnik_id) return null;
  return (
    <div class="ploca stog" id="kontakt">
      <h2>Kontaktiraj prodavatelja</h2>
      {postojeci.podaci ? (
        <a class="gumb glavni sirok" href={adresa(`/poruke/${postojeci.podaci}`)}>
          Otvori razgovor
        </a>
      ) : (
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setSalje(true);
            setGreska('');
            try {
              const id = await backend.zapocniRazgovor(oglas.id, tekst);
              obavijest('Poruka je poslana.');
              idi(`/poruke/${id}`);
            } catch (err) {
              setGreska((err as Error).message);
            } finally {
              setSalje(false);
            }
          }}
        >
          <label class="polje">
            <span>Poruka</span>
            <textarea value={tekst} maxLength={2000} onInput={(e) => setTekst(e.currentTarget.value)} />
          </label>
          {greska && <div class="greska">{greska}</div>}
          <button class="gumb glavni sirok" type="submit" disabled={salje || !tekst.trim()}>
            {salje ? 'Šaljem…' : 'Pošalji poruku'}
          </button>
        </form>
      )}
      {oglas.prikazi_telefon &&
        (telefon ? (
          <a class="gumb sirok" href={`tel:${telefon.replace(/[^\d+]/g, '')}`}>
            📞 {telefon}
          </a>
        ) : telefon === null ? (
          <p class="pomoc">Prodavatelj nije upisao broj telefona.</p>
        ) : (
          <button
            class="gumb sirok"
            type="button"
            onClick={async () => {
              try {
                setTelefon(await backend.telefon(oglas.id));
              } catch (err) {
                obavijest((err as Error).message);
              }
            }}
          >
            📞 Prikaži telefon
          </button>
        ))}
    </div>
  );
}

function PrijaviOglas({ oglas }: { oglas: Oglas }) {
  const { ja } = useJa();
  const [otvoren, setOtvoren] = useState(false);
  const [razlog, setRazlog] = useState<RazlogPrijave>('prevara');
  const [napomena, setNapomena] = useState('');
  const [greska, setGreska] = useState('');
  if (ja?.id === oglas.korisnik_id) return null;
  return (
    <>
      <button
        class="gumb malen opasno"
        type="button"
        onClick={() => (ja ? setOtvoren(true) : idi(`/prijava?natrag=${encodeURIComponent(putOglasa(oglas))}`))}
      >
        🚩 Prijavi oglas
      </button>
      {otvoren && (
        <Dijalog naslov="Prijavi oglas" onZatvori={() => setOtvoren(false)}>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              try {
                await backend.prijaviOglas(oglas.id, razlog, napomena);
                setOtvoren(false);
                obavijest('Hvala! Prijava je poslana moderatorima.');
              } catch (err) {
                setGreska((err as Error).message);
              }
            }}
          >
            <fieldset class="polje">
              <legend>Razlog</legend>
              {RAZLOZI_PRIJAVE.map((r) => (
                <label class="kvacica" key={r.kljuc}>
                  <input
                    type="radio"
                    name="razlog"
                    value={r.kljuc}
                    checked={razlog === r.kljuc}
                    onChange={() => setRazlog(r.kljuc)}
                  />
                  {r.naziv}
                </label>
              ))}
            </fieldset>
            <label class="polje">
              <span>Napomena (neobavezno)</span>
              <textarea maxLength={1000} value={napomena} onInput={(e) => setNapomena(e.currentTarget.value)} />
            </label>
            {greska && <div class="greska">{greska}</div>}
            <div class="gumbi">
              <button class="gumb glavni" type="submit">
                Pošalji prijavu
              </button>
              <button class="gumb" type="button" onClick={() => setOtvoren(false)}>
                Odustani
              </button>
            </div>
          </form>
        </Dijalog>
      )}
    </>
  );
}

export function OglasStranica({ id }: { id: string }) {
  const { ja } = useJa();
  const r = useUcitaj(() => backend.oglas(id), [id, ja?.id]);
  const { jeFavorit, prebaci } = useFavoriti();
  const o = r.podaci;
  useEffect(() => {
    if (o) {
      postaviSeo(
        `${o.naslov} – ${cijenaTekst(o.cijena)}`,
        `${o.naslov}, ${cijenaTekst(o.cijena)}, ${o.grad}. ${o.opis}`,
        o.slike[0],
      );
      // Ispravi adresu ako je naslov u njoj zastario.
      const tocno = putOglasa(o);
      if (!location.pathname.endsWith(tocno)) idi(tocno, true);
    } else if (!r.ucitava) postaviSeo('Oglas nije pronađen');
  }, [o?.id, o?.naslov, r.ucitava]);

  if (r.greska) return <Greska poruka={r.greska} ponovno={r.ponovno} />;
  if (r.ucitava && !o) return <Ucitavanje />;
  if (!o) {
    return (
      <div class="prazno ploca">
        <h1>Oglas nije pronađen</h1>
        <p>Možda je obrisan ili uklonjen.</p>
        <a class="gumb" href={adresa('/oglasi')}>
          Pogledaj ostale oglase
        </a>
      </div>
    );
  }
  const kat = kategorija(o.kategorija);
  const vlasnik = ja?.id === o.korisnik_id;
  return (
    <div class="oglas-raspored">
      <div class="stog">
        <Galerija oglas={o} />
        <div>
          <a class="pomoc" href={adresa(`/kategorija/${o.kategorija}`)}>
            {kat?.naziv ?? o.kategorija}
          </a>
          <h1>{o.naslov}</h1>
          <div class="velika-cijena">{cijenaTekst(o.cijena)}</div>
          {o.status !== 'aktivan' || jeIstekao(o) ? (
            <p>
              <StatusOznaka oglas={o} />{' '}
              {o.status === 'prodano'
                ? 'Ovaj predmet je prodan.'
                : o.status === 'uklonjen'
                  ? `Oglas je uklonio moderator${o.uklonjeno_razlog ? `: ${o.uklonjeno_razlog}` : '.'}`
                  : 'Oglas je istekao.'}
            </p>
          ) : null}
        </div>
        <dl class="svojstva">
          <dt>Stanje</dt>
          <dd>{o.stanje}</dd>
          {kat?.polja.map((p) =>
            o.polja[p.kljuc] ? (
              <Fragment key={p.kljuc}>
                <dt>{p.naziv}</dt>
                <dd>{o.polja[p.kljuc]}</dd>
              </Fragment>
            ) : null,
          )}
          <dt>Lokacija</dt>
          <dd>
            {o.grad}, {o.zupanija}
          </dd>
          <dt>Objavljeno</dt>
          <dd>
            <time dateTime={o.objavljeno}>{datum(o.objavljeno)}</time> ({prije(o.objavljeno)})
          </dd>
        </dl>
        <section>
          <h2>Opis</h2>
          <p class="opis">{o.opis}</p>
        </section>
      </div>
      <div class="stog">
        {vlasnik ? (
          <UpravljanjeOglasom oglas={o} osvjezi={r.ponovno} />
        ) : (
          <>
            <Kontakt oglas={o} />
            <div class="gumbi">
              <button class="gumb malen" type="button" aria-pressed={jeFavorit(o.id)} onClick={() => prebaci(o.id)}>
                {jeFavorit(o.id) ? '♥ Spremljeno' : '♡ Spremi'}
              </button>
              <button
                class="gumb malen"
                type="button"
                onClick={async () => {
                  const url = location.href;
                  try {
                    if (navigator.share) await navigator.share({ title: o.naslov, url });
                    else {
                      await navigator.clipboard.writeText(url);
                      obavijest('Poveznica je kopirana.');
                    }
                  } catch {
                    /* korisnik je odustao */
                  }
                }}
              >
                ↗ Podijeli
              </button>
              <PrijaviOglas oglas={o} />
            </div>
          </>
        )}
        <Prodavatelj oglas={o} />
        <SigurnaKupnja />
      </div>
    </div>
  );
}
