import { Fragment } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { ISTEK_DANA, MAX_SLIKA } from '../config/app';
import { KATEGORIJE, STANJA, ZUPANIJE, kategorija } from '../config/kategorije';
import { backend } from '../data';
import type { NacrtOglasa, SlikaZaSpremanje } from '../data/types';
import { provjeriOglas } from '../lib/provjera';
import { idi } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { pripremiSliku } from '../lib/slike';
import { obavijest, useJa } from '../lib/stanje';
import { cijenaTekst } from '../lib/tekst';
import { Greska, MoraPrijava, SigurnaKupnja, Ucitavanje, putOglasa } from '../components/ui';

type SlikaUObrascu = SlikaZaSpremanje & { pregled: string; kljuc: string };

const prazanNacrt = (grad: string | null): NacrtOglasa => ({
  naslov: '',
  kategorija: '',
  opis: '',
  cijena: null,
  zupanija: '',
  grad: grad ?? '',
  stanje: '',
  polja: {},
  prikazi_telefon: false,
});

export function Objavi({ id }: { id?: string }) {
  useEffect(() => postaviSeo(id ? 'Uredi oglas' : 'Objavi oglas'), [id]);
  return (
    <MoraPrijava>
      <ObrazacOglasa id={id} />
    </MoraPrijava>
  );
}

function ObrazacOglasa({ id }: { id?: string }) {
  const { ja } = useJa();
  const [nacrt, setNacrt] = useState<NacrtOglasa>(() => prazanNacrt(ja?.grad ?? null));
  const [cijenaTekstPolja, setCijenaTekstPolja] = useState('');
  const [dogovor, setDogovor] = useState(false);
  const [slike, setSlike] = useState<SlikaUObrascu[]>([]);
  const [telefon, setTelefon] = useState('');
  const [korak, setKorak] = useState<'obrazac' | 'pregled'>('obrazac');
  const [greske, setGreske] = useState<Record<string, string>>({});
  const [ucitava, setUcitava] = useState(!!id);
  const [obradaSlika, setObradaSlika] = useState(false);
  const [sprema, setSprema] = useState(false);
  const [greska, setGreska] = useState('');

  useEffect(() => {
    backend.mojTelefon().then((t) => setTelefon(t ?? ''), () => {});
    if (!id) return;
    backend.oglas(id).then(
      (o) => {
        if (!o || o.korisnik_id !== ja?.id) {
          setGreska('Oglas nije pronađen.');
        } else {
          setNacrt({
            naslov: o.naslov,
            kategorija: o.kategorija,
            opis: o.opis,
            cijena: o.cijena,
            zupanija: o.zupanija,
            grad: o.grad,
            stanje: o.stanje,
            polja: o.polja,
            prikazi_telefon: o.prikazi_telefon,
          });
          setDogovor(o.cijena == null);
          setCijenaTekstPolja(o.cijena != null ? String(o.cijena) : '');
          setSlike(o.slike.map((url, i) => ({ vrsta: 'postojeca', url, mala: o.slike_male[i], pregled: o.slike_male[i], kljuc: url })));
        }
        setUcitava(false);
      },
      (e: Error) => {
        setGreska(e.message);
        setUcitava(false);
      },
    );
  }, [id]);

  const postavi = (p: Partial<NacrtOglasa>) => setNacrt((x) => ({ ...x, ...p }));
  const kat = kategorija(nacrt.kategorija);

  const konacni = (): NacrtOglasa => {
    const c = cijenaTekstPolja.trim().replace(',', '.');
    return { ...nacrt, cijena: dogovor ? null : c === '' ? NaN : Number(c) };
  };

  const dodajSlike = async (datoteke: FileList | null) => {
    if (!datoteke?.length) return;
    const slobodno = MAX_SLIKA - slike.length;
    const odabrane = [...datoteke].slice(0, slobodno);
    if (datoteke.length > slobodno) obavijest(`Najviše ${MAX_SLIKA} fotografija.`);
    setObradaSlika(true);
    try {
      const nove: SlikaUObrascu[] = [];
      for (const f of odabrane) {
        const s = await pripremiSliku(f);
        nove.push({ vrsta: 'nova', velika: s.velika, mala: s.mala, pregled: s.pregled, kljuc: s.pregled });
      }
      setSlike((x) => [...x, ...nove].slice(0, MAX_SLIKA));
      setGreske((g) => ({ ...g, slike: '' }));
    } catch (e) {
      obavijest((e as Error).message || 'Slika se ne može učitati.');
    } finally {
      setObradaSlika(false);
    }
  };

  const naPregled = (e: Event) => {
    e.preventDefault();
    const n = konacni();
    const g = provjeriOglas(n, slike.length);
    if (!dogovor && cijenaTekstPolja.trim() === '') g.cijena = 'Upiši cijenu ili odaberi "Dogovor".';
    setGreske(g);
    if (Object.keys(g).length) {
      const prvo = document.querySelector(`[data-polje="${Object.keys(g)[0]}"]`);
      prvo?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    setKorak('pregled');
    window.scrollTo(0, 0);
  };

  const objavi = async () => {
    setSprema(true);
    setGreska('');
    try {
      const n = konacni();
      if (n.prikazi_telefon && telefon.trim() && ja) {
        await backend.spremiProfil({ ime: ja.ime, grad: ja.grad, telefon: telefon.trim() });
      }
      const o = await backend.spremiOglas(n, slike, id);
      obavijest(id ? 'Promjene su spremljene.' : 'Oglas je objavljen!');
      idi(putOglasa(o), true);
    } catch (e) {
      setGreska((e as Error).message);
    } finally {
      setSprema(false);
    }
  };

  if (ucitava) return <Ucitavanje />;
  if (greska && korak === 'obrazac' && id && !nacrt.naslov) return <Greska poruka={greska} />;

  const G = ({ k }: { k: string }) => (greske[k] ? <div class="greska-polja">{greske[k]}</div> : null);

  if (korak === 'pregled') {
    const n = konacni();
    return (
      <div class="stog" style={{ maxWidth: 720 }}>
        <div class="koraci">
          <span>1. Podaci</span>›<span class="aktivan">2. Pregled</span>
        </div>
        <h1>Pregled oglasa</h1>
        <p class="pomoc">Ovako će oglas vidjeti kupci. Provjeri podatke prije objave.</p>
        <div class="ploca stog" data-pregled>
          <div class="galerija">
            <div class="glavna">
              <img src={slike[0]?.pregled} alt="" />
            </div>
            {slike.length > 1 && (
              <div class="male">
                {slike.map((s) => (
                  <button type="button" key={s.kljuc} disabled>
                    <img src={s.pregled} alt="" />
                  </button>
                ))}
              </div>
            )}
          </div>
          <div class="pomoc">{kat?.naziv}</div>
          <h2>{n.naslov}</h2>
          <div class="velika-cijena">{cijenaTekst(n.cijena)}</div>
          <dl class="svojstva">
            <dt>Stanje</dt>
            <dd>{n.stanje}</dd>
            {kat?.polja.map((p) =>
              n.polja[p.kljuc]?.trim() ? (
                <Fragment key={p.kljuc}>
                  <dt>{p.naziv}</dt>
                  <dd>{n.polja[p.kljuc]}</dd>
                </Fragment>
              ) : null,
            )}
            <dt>Lokacija</dt>
            <dd>
              {n.grad}, {n.zupanija}
            </dd>
            <dt>Telefon</dt>
            <dd>{n.prikazi_telefon ? telefon || 'nije upisan' : 'ne prikazuje se'}</dd>
          </dl>
          <p class="opis">{n.opis}</p>
        </div>
        {!id && <p class="pomoc">Oglas je aktivan {ISTEK_DANA} dana; poslije ga možeš produljiti.</p>}
        {greska && <div class="greska">{greska}</div>}
        <div class="gumbi">
          <button class="gumb glavni" type="button" disabled={sprema} onClick={objavi}>
            {sprema ? 'Spremam…' : id ? 'Spremi promjene' : 'Objavi oglas'}
          </button>
          <button class="gumb" type="button" disabled={sprema} onClick={() => setKorak('obrazac')}>
            ← Natrag na uređivanje
          </button>
        </div>
      </div>
    );
  }

  return (
    <form class="stog" style={{ maxWidth: 720 }} onSubmit={naPregled} noValidate>
      <div class="koraci">
        <span class="aktivan">1. Podaci</span>›<span>2. Pregled</span>
      </div>
      <h1>{id ? 'Uredi oglas' : 'Objavi oglas'}</h1>
      {ja?.blokiran && <div class="greska">Račun je blokiran i ne može objavljivati oglase.</div>}

      <div class="ploca">
        <fieldset class="polje" data-polje="slike">
          <legend>
            Fotografije ({slike.length}/{MAX_SLIKA}) – barem jedna
          </legend>
          <div class="slike-obrazac">
            {slike.map((s, i) => (
              <div class="slot" key={s.kljuc}>
                <img src={s.pregled} alt={`Fotografija ${i + 1}`} />
                {i === 0 && <span class="oznaka prva">Naslovna</span>}
                <button
                  type="button"
                  class="ukloni"
                  aria-label={`Ukloni fotografiju ${i + 1}`}
                  onClick={() => setSlike((x) => x.filter((_, j) => j !== i))}
                >
                  ✕
                </button>
              </div>
            ))}
            {slike.length < MAX_SLIKA && (
              <label class="slot dodaj-sliku">
                <b aria-hidden="true">+</b>
                {obradaSlika ? 'Obrađujem…' : 'Dodaj'}
                <input
                  class="sr-only"
                  type="file"
                  accept="image/*"
                  multiple
                  data-unos-slika
                  onChange={(e) => {
                    void dodajSlike(e.currentTarget.files);
                    e.currentTarget.value = '';
                  }}
                />
              </label>
            )}
          </div>
          <G k="slike" />
          <div class="pomoc">Slike se smanjuju prije slanja. Prva je naslovna.</div>
        </fieldset>
      </div>

      <div class="ploca">
        <label class="polje" data-polje="naslov">
          <span>Naslov</span>
          <input
            type="text"
            name="naslov"
            maxLength={100}
            value={nacrt.naslov}
            placeholder="npr. Charizard Base Set 4/102"
            onInput={(e) => postavi({ naslov: e.currentTarget.value })}
          />
          <G k="naslov" />
        </label>
        <label class="polje" data-polje="kategorija">
          <span>Kategorija</span>
          <select name="kategorija" value={nacrt.kategorija} onChange={(e) => postavi({ kategorija: e.currentTarget.value, polja: {} })}>
            <option value="">Odaberi…</option>
            {KATEGORIJE.map((k) => (
              <option key={k.slug} value={k.slug}>
                {k.naziv}
              </option>
            ))}
          </select>
          <G k="kategorija" />
        </label>
        {kat && kat.polja.length > 0 && (
          <div class="dva-stupca">
            {kat.polja.map((p) => (
              <label class="polje" key={p.kljuc} data-polje={`p_${p.kljuc}`}>
                <span>{p.naziv} (neobavezno)</span>
                {p.tip === 'izbor' ? (
                  <select
                    name={`p_${p.kljuc}`}
                    value={nacrt.polja[p.kljuc] ?? ''}
                    onChange={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.currentTarget.value } })}
                  >
                    <option value="">–</option>
                    {p.opcije.map((o) => (
                      <option key={o}>{o}</option>
                    ))}
                  </select>
                ) : (
                  <input
                    type={p.tip === 'broj' ? 'number' : 'text'}
                    name={`p_${p.kljuc}`}
                    inputMode={p.tip === 'broj' ? 'numeric' : undefined}
                    placeholder={p.tip === 'tekst' ? p.placeholder : undefined}
                    value={nacrt.polja[p.kljuc] ?? ''}
                    onInput={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.currentTarget.value } })}
                  />
                )}
                <G k={`p_${p.kljuc}`} />
              </label>
            ))}
          </div>
        )}
        <fieldset class="polje" data-polje="stanje">
          <legend>Stanje</legend>
          <div class="gumbi">
            {STANJA.map((s) => (
              <label class="kvacica" key={s} style={{ marginRight: 8 }}>
                <input type="radio" name="stanje" value={s} checked={nacrt.stanje === s} onChange={() => postavi({ stanje: s })} />
                {s}
              </label>
            ))}
          </div>
          <G k="stanje" />
        </fieldset>
        <label class="polje" data-polje="opis">
          <span>Opis</span>
          <textarea
            name="opis"
            maxLength={5000}
            value={nacrt.opis}
            placeholder="Stanje, izdanje, nedostaci, što je uključeno…"
            onInput={(e) => postavi({ opis: e.currentTarget.value })}
          />
          <G k="opis" />
        </label>
      </div>

      <div class="ploca">
        <fieldset class="polje" data-polje="cijena">
          <legend>Cijena</legend>
          <div class="dva-stupca">
            <label class="polje" style={{ marginBottom: 0 }}>
              <span class="sr-only">Cijena u eurima</span>
              <input
                type="number"
                name="cijena"
                inputMode="decimal"
                min={0}
                step="0.01"
                placeholder="€"
                disabled={dogovor}
                value={dogovor ? '' : cijenaTekstPolja}
                onInput={(e) => setCijenaTekstPolja(e.currentTarget.value)}
              />
            </label>
            <label class="kvacica">
              <input type="checkbox" name="dogovor" checked={dogovor} onChange={(e) => setDogovor(e.currentTarget.checked)} />
              Dogovor
            </label>
          </div>
          <G k="cijena" />
        </fieldset>
        <div class="dva-stupca">
          <label class="polje" data-polje="zupanija">
            <span>Županija</span>
            <select name="zupanija" value={nacrt.zupanija} onChange={(e) => postavi({ zupanija: e.currentTarget.value })}>
              <option value="">Odaberi…</option>
              {ZUPANIJE.map((z) => (
                <option key={z}>{z}</option>
              ))}
            </select>
            <G k="zupanija" />
          </label>
          <label class="polje" data-polje="grad">
            <span>Grad / mjesto</span>
            <input type="text" name="grad" maxLength={60} value={nacrt.grad} onInput={(e) => postavi({ grad: e.currentTarget.value })} />
            <G k="grad" />
          </label>
        </div>
        <label class="kvacica">
          <input
            type="checkbox"
            checked={nacrt.prikazi_telefon}
            onChange={(e) => postavi({ prikazi_telefon: e.currentTarget.checked })}
          />
          Prikaži moj broj telefona prijavljenim korisnicima
        </label>
        {nacrt.prikazi_telefon && (
          <label class="polje">
            <span>Broj telefona</span>
            <input type="tel" maxLength={30} value={telefon} onInput={(e) => setTelefon(e.currentTarget.value)} />
          </label>
        )}
      </div>

      <SigurnaKupnja />
      <button class="gumb glavni sirok" type="submit" disabled={obradaSlika || ja?.blokiran}>
        Pregled oglasa →
      </button>
    </form>
  );
}
