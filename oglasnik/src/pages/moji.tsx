import { useEffect, useState } from 'preact/hooks';
import { ISTEK_DANA } from '../config/app';
import { backend } from '../data';
import type { Oglas } from '../data/types';
import { jeAktivan, jeIstekao } from '../lib/pretraga';
import { adresa, idi } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { obavijest, useUcitaj } from '../lib/stanje';
import { cijenaTekst, danaDoIsteka, datum } from '../lib/tekst';
import { Dijalog, Greska, MoraPrijava, StatusOznaka, Ucitavanje, putOglasa } from '../components/ui';

/** Radnje vlasnika: uredi, produlji, označi prodano, obriši, kontakti. */
export function UpravljanjeOglasom({ oglas, osvjezi, kompaktno }: { oglas: Oglas; osvjezi: () => void; kompaktno?: boolean }) {
  const [prodaja, setProdaja] = useState(false);
  const [brisanje, setBrisanje] = useState(false);
  const [kontakti, setKontakti] = useState(false);
  const [cijena, setCijena] = useState(oglas.cijena != null ? String(oglas.cijena) : '');
  const [radi, setRadi] = useState(false);
  const izvrsi = async (fn: () => Promise<void>, poruka: string) => {
    setRadi(true);
    try {
      await fn();
      obavijest(poruka);
      osvjezi();
    } catch (e) {
      obavijest((e as Error).message);
    } finally {
      setRadi(false);
    }
  };
  const aktivan = jeAktivan(oglas);
  const istekao = jeIstekao(oglas);
  const mozeUredivati = oglas.status === 'aktivan' || oglas.status === 'prodano';
  return (
    <div class={kompaktno ? '' : 'ploca stog'}>
      {!kompaktno && (
        <div>
          <h2>Tvoj oglas</h2>
          <StatusOznaka oglas={oglas} />{' '}
          {aktivan && <span class="pomoc">Istječe za {danaDoIsteka(oglas.istjece)} dana ({datum(oglas.istjece)})</span>}
          {oglas.status === 'prodano' && (
            <span class="pomoc">
              Prodano {oglas.prodano_datum ? datum(oglas.prodano_datum) : ''}
              {oglas.prodano_cijena != null ? ` za ${cijenaTekst(oglas.prodano_cijena)}` : ''}
            </span>
          )}
        </div>
      )}
      <div class="gumbi">
        {mozeUredivati && (
          <a class="gumb malen" href={adresa(`/oglas/${oglas.id}/uredi`)}>
            ✏️ Uredi
          </a>
        )}
        {oglas.status === 'aktivan' && (
          <button
            class="gumb malen"
            type="button"
            disabled={radi}
            onClick={() => izvrsi(() => backend.produlji(oglas.id), `Oglas je produljen za ${ISTEK_DANA} dana.`)}
          >
            {istekao ? '🔄 Obnovi' : '⏱ Produlji'}
          </button>
        )}
        {oglas.status === 'aktivan' && (
          <button class="gumb malen" type="button" disabled={radi} onClick={() => setProdaja(true)}>
            ✅ Označi kao prodano
          </button>
        )}
        {oglas.status !== 'uklonjen' && (
          <button class="gumb malen" type="button" onClick={() => setKontakti(true)}>
            👥 Kontakti
          </button>
        )}
        <button class="gumb malen opasno" type="button" disabled={radi} onClick={() => setBrisanje(true)}>
          🗑 Obriši
        </button>
      </div>
      {prodaja && (
        <Dijalog naslov="Označi kao prodano" onZatvori={() => setProdaja(false)}>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const c = cijena.trim() === '' ? null : Number(cijena.replace(',', '.'));
              if (c != null && (!Number.isFinite(c) || c < 0)) {
                obavijest('Upiši ispravnu cijenu ili ostavi prazno.');
                return;
              }
              setProdaja(false);
              void izvrsi(() => backend.oznaciProdano(oglas.id, c), 'Oglas je označen kao prodan.');
            }}
          >
            <label class="polje">
              <span>Konačna cijena u € (neobavezno)</span>
              <input
                type="number"
                inputMode="decimal"
                min={0}
                step="0.01"
                value={cijena}
                onInput={(e) => setCijena(e.currentTarget.value)}
              />
            </label>
            <p class="pomoc">Cijena se ne prikazuje kupcima; služi samo tebi i statistici.</p>
            <div class="gumbi">
              <button class="gumb glavni" type="submit">
                Označi prodano
              </button>
              <button class="gumb" type="button" onClick={() => setProdaja(false)}>
                Odustani
              </button>
            </div>
          </form>
        </Dijalog>
      )}
      {brisanje && (
        <Dijalog naslov="Obrisati oglas?" onZatvori={() => setBrisanje(false)}>
          <p>Oglas "{oglas.naslov}" više neće biti vidljiv. Razgovori o njemu ostaju u porukama.</p>
          <div class="gumbi">
            <button
              class="gumb opasno"
              type="button"
              onClick={() => {
                setBrisanje(false);
                void izvrsi(async () => {
                  await backend.obrisi(oglas.id);
                  if (location.pathname.includes(`/oglas/${oglas.id}`)) idi('/moji-oglasi', true);
                }, 'Oglas je obrisan.');
              }}
            >
              Obriši
            </button>
            <button class="gumb" type="button" onClick={() => setBrisanje(false)}>
              Odustani
            </button>
          </div>
        </Dijalog>
      )}
      {kontakti && <KontaktiDijalog oglas={oglas} onZatvori={() => setKontakti(false)} />}
    </div>
  );
}

function KontaktiDijalog({ oglas, onZatvori }: { oglas: Oglas; onZatvori: () => void }) {
  const k = useUcitaj(() => backend.kontakti(oglas.id), [oglas.id]);
  return (
    <Dijalog naslov="Tko te kontaktirao" onZatvori={onZatvori}>
      {k.greska && <Greska poruka={k.greska} />}
      {k.ucitava && <Ucitavanje />}
      {k.podaci &&
        (k.podaci.length === 0 ? (
          <p class="pomoc">Još nitko nije poslao poruku ni pogledao tvoj broj.</p>
        ) : (
          <>
            <p>
              {k.podaci.filter((x) => x.vrsta === 'poruka').length} poruka ·{' '}
              {k.podaci.filter((x) => x.vrsta === 'telefon').length} prikaza telefona
            </p>
            <ul>
              {k.podaci.slice(0, 50).map((x) => (
                <li key={x.id}>
                  {x.vrsta === 'poruka' ? 'Poruka' : 'Prikaz telefona'} · {datum(x.kreirano)}
                </li>
              ))}
            </ul>
          </>
        ))}
      <button class="gumb" type="button" onClick={onZatvori}>
        Zatvori
      </button>
    </Dijalog>
  );
}

type Tab = 'aktivni' | 'istekli' | 'prodani' | 'uklonjeni';
const TABOVI: { kljuc: Tab; naziv: string; uvjet: (o: Oglas) => boolean }[] = [
  { kljuc: 'aktivni', naziv: 'Aktivni', uvjet: (o) => jeAktivan(o) },
  { kljuc: 'istekli', naziv: 'Istekli', uvjet: (o) => jeIstekao(o) },
  { kljuc: 'prodani', naziv: 'Prodani', uvjet: (o) => o.status === 'prodano' },
  { kljuc: 'uklonjeni', naziv: 'Uklonjeni', uvjet: (o) => o.status === 'uklonjen' },
];

export function MojiOglasi() {
  useEffect(() => postaviSeo('Moji oglasi'), []);
  return (
    <MoraPrijava>
      <MojiOglasiSadrzaj />
    </MoraPrijava>
  );
}

function MojiOglasiSadrzaj() {
  const r = useUcitaj(() => backend.mojiOglasi(), []);
  const [tab, setTab] = useState<Tab>('aktivni');
  const svi = r.podaci ?? [];
  const t = TABOVI.find((x) => x.kljuc === tab)!;
  const popis = svi.filter(t.uvjet);
  return (
    <>
      <div class="odjeljak-naslov">
        <h1>Moji oglasi</h1>
        <a class="gumb glavni malen" href={adresa('/objavi')}>
          + Novi oglas
        </a>
      </div>
      <div class="kartice-tabovi" role="tablist">
        {TABOVI.map((x) => (
          <button key={x.kljuc} role="tab" type="button" aria-selected={tab === x.kljuc} onClick={() => setTab(x.kljuc)}>
            {x.naziv} ({svi.filter(x.uvjet).length})
          </button>
        ))}
      </div>
      {r.greska && <Greska poruka={r.greska} ponovno={r.ponovno} />}
      {r.ucitava && !r.podaci && <Ucitavanje />}
      {r.podaci && popis.length === 0 && (
        <div class="prazno ploca">
          {tab === 'aktivni' ? 'Nemaš aktivnih oglasa.' : 'Ovdje još nema oglasa.'}
        </div>
      )}
      {popis.map((o) => (
        <div class="redak" key={o.id} data-moj-oglas={o.id}>
          <a class="slicica" href={adresa(putOglasa(o))}>
            <img src={o.slike_male[0]} alt="" loading="lazy" />
          </a>
          <div class="tijelo stog">
            <div>
              <a class="naslov" href={adresa(putOglasa(o))}>
                {o.naslov}
              </a>
              <div>
                <b>{cijenaTekst(o.cijena)}</b> · <StatusOznaka oglas={o} />
              </div>
              <div class="pomoc">
                {jeAktivan(o)
                  ? `Istječe za ${danaDoIsteka(o.istjece)} dana`
                  : o.status === 'prodano'
                    ? `Prodano ${o.prodano_datum ? datum(o.prodano_datum) : ''}${o.prodano_cijena != null ? ` za ${cijenaTekst(o.prodano_cijena)}` : ''}`
                    : o.status === 'uklonjen'
                      ? `Uklonio moderator${o.uklonjeno_razlog ? `: ${o.uklonjeno_razlog}` : ''}`
                      : `Istekao ${datum(o.istjece)}`}
              </div>
            </div>
            <UpravljanjeOglasom oglas={o} osvjezi={r.ponovno} kompaktno />
          </div>
        </div>
      ))}
    </>
  );
}
