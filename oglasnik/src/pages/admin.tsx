import { useEffect, useState } from 'preact/hooks';
import { RAZLOZI_PRIJAVE } from '../config/kategorije';
import { backend } from '../data';
import { adresa } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { obavijest, useJa, useUcitaj } from '../lib/stanje';
import { datum } from '../lib/tekst';
import { Greska, MoraPrijava, Ucitavanje, putOglasa } from '../components/ui';

export function Admin() {
  useEffect(() => postaviSeo('Moderacija'), []);
  return (
    <MoraPrijava>
      <AdminSadrzaj />
    </MoraPrijava>
  );
}

function AdminSadrzaj() {
  const { ja } = useJa();
  const [tab, setTab] = useState<'prijave' | 'korisnici'>('prijave');
  if (!ja?.admin) return <div class="prazno ploca">Ova stranica je samo za administratore.</div>;
  return (
    <>
      <h1>Moderacija</h1>
      <div class="kartice-tabovi" role="tablist">
        <button role="tab" type="button" aria-selected={tab === 'prijave'} onClick={() => setTab('prijave')}>
          Prijavljeni oglasi
        </button>
        <button role="tab" type="button" aria-selected={tab === 'korisnici'} onClick={() => setTab('korisnici')}>
          Korisnici
        </button>
      </div>
      {tab === 'prijave' ? <Prijave /> : <Korisnici />}
    </>
  );
}

const nazivRazloga = (k: string) => RAZLOZI_PRIJAVE.find((r) => r.kljuc === k)?.naziv ?? k;

function Prijave() {
  const r = useUcitaj(() => backend.prijave(), []);
  const [samoOtvorene, setSamoOtvorene] = useState(true);
  const radnja = async (fn: () => Promise<void>, poruka: string) => {
    try {
      await fn();
      obavijest(poruka);
      r.ponovno();
    } catch (e) {
      obavijest((e as Error).message);
    }
  };
  if (r.greska) return <Greska poruka={r.greska} ponovno={r.ponovno} />;
  if (!r.podaci) return <Ucitavanje />;
  const popis = r.podaci.filter((p) => !samoOtvorene || p.status === 'otvorena');
  return (
    <>
      <label class="kvacica">
        <input type="checkbox" checked={samoOtvorene} onChange={(e) => setSamoOtvorene(e.currentTarget.checked)} />
        Samo otvorene prijave
      </label>
      {popis.length === 0 && <div class="prazno ploca">Nema prijava.</div>}
      {popis.map((p) => (
        <div class="redak" key={p.id} data-prijava={p.id}>
          <div class="tijelo stog">
            <div>
              <div class="naslov">
                {p.oglas ? <a href={adresa(putOglasa(p.oglas))}>{p.oglas.naslov}</a> : 'Oglas više ne postoji'}{' '}
                <span class={`oznaka ${p.status === 'otvorena' ? 'crvena' : 'siva'}`}>
                  {p.status === 'otvorena' ? 'Otvorena' : 'Riješena'}
                </span>
              </div>
              <div>
                <b>{nazivRazloga(p.razlog)}</b> · {datum(p.kreirano)}
                {p.oglas && ` · oglas: ${p.oglas.status}`}
              </div>
              {p.napomena && <div class="opis">{p.napomena}</div>}
            </div>
            <div class="gumbi">
              {p.oglas && p.oglas.status !== 'uklonjen' && (
                <button
                  class="gumb malen opasno"
                  type="button"
                  onClick={() =>
                    radnja(async () => {
                      await backend.ukloniOglas(p.oglas!.id, nazivRazloga(p.razlog));
                      await backend.rijesiPrijavu(p.id);
                    }, 'Oglas je uklonjen.')
                  }
                >
                  Ukloni oglas
                </button>
              )}
              {p.oglas && (
                <button
                  class="gumb malen opasno"
                  type="button"
                  onClick={() => radnja(() => backend.blokiraj(p.oglas!.korisnik_id, true), 'Korisnik je blokiran.')}
                >
                  Blokiraj prodavatelja
                </button>
              )}
              {p.status === 'otvorena' && (
                <button class="gumb malen" type="button" onClick={() => radnja(() => backend.rijesiPrijavu(p.id), 'Prijava je zatvorena.')}>
                  Zatvori bez radnje
                </button>
              )}
            </div>
          </div>
        </div>
      ))}
    </>
  );
}

function Korisnici() {
  const { ja } = useJa();
  const r = useUcitaj(() => backend.korisnici(), []);
  if (r.greska) return <Greska poruka={r.greska} ponovno={r.ponovno} />;
  if (!r.podaci) return <Ucitavanje />;
  return (
    <div class="tablica-omot">
      <table class="admin">
        <thead>
          <tr>
            <th>Ime</th>
            <th>Registriran</th>
            <th>Status</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {r.podaci.map((k) => (
            <tr key={k.id}>
              <td>
                <a href={adresa(`/korisnik/${k.id}`)}>{k.ime}</a>
                {k.admin && ' (admin)'}
              </td>
              <td>{datum(k.registriran)}</td>
              <td>{k.blokiran ? <span class="oznaka crvena">Blokiran</span> : 'Aktivan'}</td>
              <td>
                {k.id !== ja?.id && (
                  <button
                    class={`gumb malen ${k.blokiran ? '' : 'opasno'}`}
                    type="button"
                    onClick={async () => {
                      try {
                        await backend.blokiraj(k.id, !k.blokiran);
                        obavijest(k.blokiran ? 'Blokada je skinuta.' : 'Korisnik je blokiran.');
                        r.ponovno();
                      } catch (e) {
                        obavijest((e as Error).message);
                      }
                    }}
                  >
                    {k.blokiran ? 'Odblokiraj' : 'Blokiraj'}
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
