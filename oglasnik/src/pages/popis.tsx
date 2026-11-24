import { useEffect, useRef, useState } from 'preact/hooks';
import { APP_NAME, APP_SLOGAN } from '../config/app';
import { KATEGORIJE, STANJA, ZUPANIJE, kategorija } from '../config/kategorije';
import { backend } from '../data';
import type { Filteri, Oglas } from '../data/types';
import { adresaIzFiltera, filteriIzAdrese } from '../lib/pretraga';
import { adresa, idi } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { useUcitaj } from '../lib/stanje';
import { Greska, Mreza, Ucitavanje } from '../components/ui';

function TrazilicaForma({ pocetno, kategorijaSlug }: { pocetno?: string; kategorijaSlug?: string }) {
  const [q, setQ] = useState(pocetno ?? '');
  useEffect(() => setQ(pocetno ?? ''), [pocetno]);
  return (
    <form
      class="pretraga-velika"
      role="search"
      onSubmit={(e) => {
        e.preventDefault();
        const base = kategorijaSlug ? `/kategorija/${kategorijaSlug}` : '/oglasi';
        idi(base + adresaIzFiltera({ q: q.trim() || undefined }));
      }}
    >
      <label class="sr-only" for="trazi">
        Pretraži oglase
      </label>
      <input
        id="trazi"
        type="search"
        placeholder="Što tražiš? npr. Charizard, kovanica 1 kuna…"
        value={q}
        onInput={(e) => setQ(e.currentTarget.value)}
        enterKeyHint="search"
      />
      <button class="gumb glavni" type="submit">
        Traži
      </button>
    </form>
  );
}

export function Pocetna() {
  useEffect(() => postaviSeo(null), []);
  const najnoviji = useUcitaj(() => backend.trazi({ sort: 'najnovije' }, 0), []);
  return (
    <>
      <section class="uvod">
        <h1>{APP_SLOGAN}</h1>
        <p class="pomoc">
          Objavi oglas besplatno, pronađi ono što skupljaš i dogovori se izravno s prodavateljem.
        </p>
        <TrazilicaForma />
      </section>
      <h2>Kategorije</h2>
      <nav class="kategorije" aria-label="Kategorije">
        {KATEGORIJE.map((k) => (
          <a key={k.slug} class="kategorija-plocica" href={adresa(`/kategorija/${k.slug}`)}>
            <span aria-hidden="true">{k.ikona}</span>
            <span>{k.naziv}</span>
          </a>
        ))}
      </nav>
      <div class="odjeljak-naslov">
        <h2>Najnoviji oglasi</h2>
        <a href={adresa('/oglasi')}>Svi oglasi ›</a>
      </div>
      {najnoviji.greska ? (
        <Greska poruka={najnoviji.greska} ponovno={najnoviji.ponovno} />
      ) : najnoviji.ucitava && !najnoviji.podaci ? (
        <Ucitavanje />
      ) : najnoviji.podaci!.stavke.length === 0 ? (
        <div class="prazno ploca">
          <p>Još nema oglasa. Budi prvi!</p>
          <a class="gumb glavni" href={adresa('/objavi')}>
            Objavi oglas
          </a>
        </div>
      ) : (
        <Mreza oglasi={najnoviji.podaci!.stavke.slice(0, 12)} />
      )}
    </>
  );
}

function FilterPanel({ f, kategorijaSlug, promijeni }: { f: Filteri; kategorijaSlug?: string; promijeni: (f: Filteri) => void }) {
  const [nacrt, setNacrt] = useState<Filteri>(f);
  useEffect(() => setNacrt(f), [JSON.stringify(f)]);
  const kat = kategorija(kategorijaSlug ?? nacrt.kategorija);
  const broj = (v: string) => (v.trim() === '' ? undefined : Number(v.replace(',', '.')));
  const postavi = (p: Partial<Filteri>) => setNacrt((x) => ({ ...x, ...p }));
  const otvoreno = typeof window !== 'undefined' && window.matchMedia?.('(min-width: 900px)').matches;
  return (
    <details class="ploca filteri" open={otvoreno}>
      <summary>Filteri</summary>
      <form
        style={{ marginTop: 12 }}
        onSubmit={(e) => {
          e.preventDefault();
          promijeni(nacrt);
        }}
      >
        {!kategorijaSlug && (
          <label class="polje">
            <span>Kategorija</span>
            <select
              value={nacrt.kategorija ?? ''}
              onChange={(e) => postavi({ kategorija: e.currentTarget.value || undefined, polja: {} })}
            >
              <option value="">Sve kategorije</option>
              {KATEGORIJE.map((k) => (
                <option key={k.slug} value={k.slug}>
                  {k.naziv}
                </option>
              ))}
            </select>
          </label>
        )}
        <fieldset class="polje">
          <legend>Cijena (€)</legend>
          <div class="dva-stupca">
            <input
              type="number"
              inputMode="decimal"
              min={0}
              placeholder="od"
              aria-label="Cijena od"
              value={nacrt.cijenaOd ?? ''}
              onInput={(e) => postavi({ cijenaOd: broj(e.currentTarget.value) })}
            />
            <input
              type="number"
              inputMode="decimal"
              min={0}
              placeholder="do"
              aria-label="Cijena do"
              value={nacrt.cijenaDo ?? ''}
              onInput={(e) => postavi({ cijenaDo: broj(e.currentTarget.value) })}
            />
          </div>
        </fieldset>
        <label class="polje">
          <span>Županija</span>
          <select value={nacrt.zupanija ?? ''} onChange={(e) => postavi({ zupanija: e.currentTarget.value || undefined })}>
            <option value="">Sve županije</option>
            {ZUPANIJE.map((z) => (
              <option key={z}>{z}</option>
            ))}
          </select>
        </label>
        <label class="polje">
          <span>Grad</span>
          <input
            type="text"
            value={nacrt.grad ?? ''}
            onInput={(e) => postavi({ grad: e.currentTarget.value || undefined })}
          />
        </label>
        <label class="polje">
          <span>Stanje</span>
          <select value={nacrt.stanje ?? ''} onChange={(e) => postavi({ stanje: e.currentTarget.value || undefined })}>
            <option value="">Bilo koje</option>
            {STANJA.map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        {kat?.polja.map((p) => (
          <label class="polje" key={p.kljuc}>
            <span>{p.naziv}</span>
            {p.tip === 'izbor' ? (
              <select
                value={nacrt.polja?.[p.kljuc] ?? ''}
                onChange={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.currentTarget.value } })}
              >
                <option value="">Bilo koje</option>
                {p.opcije.map((o) => (
                  <option key={o}>{o}</option>
                ))}
              </select>
            ) : (
              <input
                type={p.tip === 'broj' ? 'number' : 'text'}
                value={nacrt.polja?.[p.kljuc] ?? ''}
                onInput={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.currentTarget.value } })}
              />
            )}
          </label>
        ))}
        <div class="gumbi">
          <button class="gumb glavni" type="submit">
            Primijeni
          </button>
          <button
            class="gumb"
            type="button"
            onClick={() => promijeni({ q: f.q, sort: f.sort })}
          >
            Očisti
          </button>
        </div>
      </form>
    </details>
  );
}

/** /oglasi i /kategorija/:slug — pretraga, filteri, sortiranje, učitavanje dalje. */
export function Popis({ upit, kategorijaSlug }: { upit: URLSearchParams; kategorijaSlug?: string }) {
  const f: Filteri = { ...filteriIzAdrese(upit) };
  if (kategorijaSlug) f.kategorija = kategorijaSlug;
  const kat = kategorija(f.kategorija);
  const kljuc = JSON.stringify(f);
  const [oglasi, setOglasi] = useState<Oglas[]>([]);
  const [ukupno, setUkupno] = useState(0);
  const [stranica, setStranica] = useState(0);
  const [stanje, setStanje] = useState<'ucitava' | 'gotovo' | 'greska'>('ucitava');
  const [greska, setGreska] = useState('');
  const zahtjev = useRef(0);

  const ucitaj = (s: number) => {
    const broj = ++zahtjev.current;
    setStanje('ucitava');
    backend.trazi(f, s).then(
      (r) => {
        if (broj !== zahtjev.current) return;
        setOglasi((x) => (s === 0 ? r.stavke : [...x, ...r.stavke]));
        setUkupno(r.ukupno);
        setStranica(s);
        setStanje('gotovo');
      },
      (e: Error) => {
        if (broj !== zahtjev.current) return;
        setGreska(e.message);
        setStanje('greska');
      },
    );
  };
  useEffect(() => {
    setOglasi([]);
    ucitaj(0);
    const naslov = kat ? kat.naziv : f.q ? `Pretraga: ${f.q}` : 'Svi oglasi';
    postaviSeo(naslov, kat ? `${kat.naziv}: ${kat.opis}. Oglasi kolekcionara na ${APP_NAME}.` : undefined);
  }, [kljuc]);

  // Beskonačno učitavanje: kad se dno popisa pojavi, učitaj sljedeću stranicu.
  const dno = useRef<HTMLDivElement>(null);
  const imaJos = oglasi.length < ukupno;
  useEffect(() => {
    const el = dno.current;
    if (!el || !imaJos || stanje !== 'gotovo' || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((e) => e[0].isIntersecting && ucitaj(stranica + 1), { rootMargin: '400px' });
    io.observe(el);
    return () => io.disconnect();
  }, [imaJos, stanje, stranica, kljuc]);

  const promijeni = (novi: Filteri) => {
    const base = kategorijaSlug ? `/kategorija/${kategorijaSlug}` : '/oglasi';
    if (kategorijaSlug) delete novi.kategorija;
    idi(base + adresaIzFiltera(novi));
  };

  return (
    <>
      <h1>{kat ? kat.naziv : 'Oglasi'}</h1>
      <div style={{ marginBottom: 12 }}>
        <TrazilicaForma pocetno={f.q} kategorijaSlug={kategorijaSlug} />
      </div>
      <div class="popis-raspored">
        <FilterPanel f={f} kategorijaSlug={kategorijaSlug} promijeni={promijeni} />
        <section aria-live="polite">
          <div class="alatna-traka">
            <span class="pomoc" data-ukupno={ukupno}>
              {stanje === 'ucitava' && oglasi.length === 0 ? 'Tražim…' : `${ukupno} ${ukupno === 1 ? 'oglas' : 'oglasa'}`}
            </span>
            <label>
              <span class="sr-only">Sortiraj</span>
              <select
                value={f.sort ?? 'najnovije'}
                onChange={(e) => promijeni({ ...f, sort: e.currentTarget.value as Filteri['sort'] })}
              >
                <option value="najnovije">Najnovije</option>
                <option value="cijena_rastuce">Cijena: od najniže</option>
                <option value="cijena_padajuce">Cijena: od najviše</option>
              </select>
            </label>
          </div>
          {stanje === 'greska' && <Greska poruka={greska} ponovno={() => ucitaj(stranica)} />}
          {oglasi.length > 0 && <Mreza oglasi={oglasi} />}
          {stanje === 'gotovo' && oglasi.length === 0 && (
            <div class="prazno ploca">
              <p>Nema oglasa za ovu pretragu.</p>
              <p class="pomoc">Probaj s manje filtera ili drugom riječi.</p>
            </div>
          )}
          {stanje === 'ucitava' && <Ucitavanje />}
          <div ref={dno} />
          {imaJos && stanje === 'gotovo' && (
            <div style={{ textAlign: 'center', marginTop: 16 }}>
              <button class="gumb" type="button" onClick={() => ucitaj(stranica + 1)}>
                Učitaj još
              </button>
            </div>
          )}
        </section>
      </div>
    </>
  );
}
