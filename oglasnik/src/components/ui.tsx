import type { ComponentChildren } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { kategorija } from '../config/kategorije';
import { backend } from '../data';
import type { Oglas } from '../data/types';
import { jeIstekao } from '../lib/pretraga';
import { adresa, idi } from '../lib/router';
import { obavijest, useJa } from '../lib/stanje';
import { cijenaTekst, prije, slug } from '../lib/tekst';

export const putOglasa = (o: Pick<Oglas, 'id' | 'naslov'>) => `/oglas/${o.id}/${slug(o.naslov)}`;

/** Favoriti prijavljenog korisnika, dijeljeni među karticama. */
let favoriti: Set<string> | null = null;
let ucitavanjeFavorita: Promise<Set<string>> | null = null;
const favSlusatelji = new Set<() => void>();
export function zaboraviFavorite() {
  favoriti = null;
  ucitavanjeFavorita = null;
  favSlusatelji.forEach((cb) => cb());
}
backend.naPromjenuPrijave(zaboraviFavorite);

export function useFavoriti() {
  const { ja } = useJa();
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((x) => x + 1);
    favSlusatelji.add(cb);
    if (ja && !favoriti && !ucitavanjeFavorita) {
      ucitavanjeFavorita = backend.favoritIds().then((s) => {
        favoriti = s;
        favSlusatelji.forEach((f) => f());
        return s;
      });
    }
    return () => {
      favSlusatelji.delete(cb);
    };
  }, [ja?.id]);
  const prebaci = async (id: string) => {
    if (!ja) {
      idi(`/prijava?natrag=${encodeURIComponent(location.pathname.slice(import.meta.env.BASE_URL.length - 1))}`);
      return;
    }
    const da = !favoriti?.has(id);
    try {
      await backend.postaviFavorit(id, da);
      favoriti = new Set(favoriti ?? []);
      if (da) favoriti.add(id);
      else favoriti.delete(id);
      favSlusatelji.forEach((f) => f());
      obavijest(da ? 'Spremljeno u favorite.' : 'Uklonjeno iz favorita.');
    } catch (e) {
      obavijest((e as Error).message);
    }
  };
  return { jeFavorit: (id: string) => !!favoriti?.has(id), prebaci };
}

export function OglasKartica({ oglas }: { oglas: Oglas }) {
  const { jeFavorit, prebaci } = useFavoriti();
  const fav = jeFavorit(oglas.id);
  return (
    <article class="kartica" data-oglas={oglas.id}>
      <a class="sadrzaj" href={adresa(putOglasa(oglas))}>
        <div class="slika">
          <img src={oglas.slike_male[0]} alt="" loading="lazy" decoding="async" width={240} height={240} />
        </div>
        <div class="tekst">
          <div class="naslov">{oglas.naslov}</div>
          <div class="cijena">{cijenaTekst(oglas.cijena)}</div>
          <div class="mjesto">
            {oglas.grad} · {prije(oglas.objavljeno)}
          </div>
        </div>
      </a>
      {oglas.status === 'prodano' && <span class="oznaka oznaka-na-slici">Prodano</span>}
      <button
        class="srce"
        type="button"
        aria-pressed={fav}
        aria-label={fav ? 'Ukloni iz favorita' : 'Spremi u favorite'}
        onClick={() => prebaci(oglas.id)}
      >
        {fav ? '♥' : '♡'}
      </button>
    </article>
  );
}

export function Mreza({ oglasi }: { oglasi: Oglas[] }) {
  return (
    <div class="mreza">
      {oglasi.map((o) => (
        <OglasKartica key={o.id} oglas={o} />
      ))}
    </div>
  );
}

export function StatusOznaka({ oglas }: { oglas: Oglas }) {
  if (oglas.status === 'prodano') return <span class="oznaka">Prodano</span>;
  if (oglas.status === 'uklonjen') return <span class="oznaka crvena">Uklonjen</span>;
  if (oglas.status === 'obrisan') return <span class="oznaka siva">Obrisan</span>;
  if (jeIstekao(oglas)) return <span class="oznaka siva">Istekao</span>;
  return <span class="oznaka">Aktivan</span>;
}

export function Dijalog(props: { naslov: string; children: ComponentChildren; onZatvori: () => void }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === 'Escape' && props.onZatvori();
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, []);
  return (
    <div class="zastor" onClick={(e) => e.target === e.currentTarget && props.onZatvori()}>
      <div class="dijalog" role="dialog" aria-modal="true" aria-label={props.naslov}>
        <h2>{props.naslov}</h2>
        {props.children}
      </div>
    </div>
  );
}

export function SigurnaKupnja() {
  return (
    <aside class="upozorenje" aria-label="Savjeti za sigurnu kupnju">
      <strong>⚠️ Sigurna kupnja</strong>
      <ul>
        <li>Najsigurnije je osobno preuzimanje: pregledaj predmet prije plaćanja.</li>
        <li>Budi oprezan kod plaćanja unaprijed i nikad ne šalji podatke kartice ni kodove.</li>
        <li>Kod skupljih predmeta traži dodatne fotografije, certifikat ili dokaz porijekla.</li>
        <li>Sumnjiv oglas prijavi gumbom "Prijavi oglas".</li>
      </ul>
    </aside>
  );
}

export const Kategorija = ({ slug: s }: { slug: string }) => <>{kategorija(s)?.naziv ?? s}</>;

export function Ucitavanje() {
  return (
    <div class="ucitavanje" role="status">
      Učitavam…
    </div>
  );
}

export function Greska({ poruka, ponovno }: { poruka: string; ponovno?: () => void }) {
  return (
    <div class="greska" role="alert">
      {poruka}{' '}
      {ponovno && (
        <button class="gumb malen" type="button" onClick={ponovno}>
          Pokušaj ponovno
        </button>
      )}
    </div>
  );
}

/** Stranica samo za prijavljene: inače vodi na prijavu i vraća natrag. */
export function MoraPrijava({ children }: { children: ComponentChildren }) {
  const { ja, ucitano } = useJa();
  useEffect(() => {
    if (ucitano && !ja) {
      const natrag = location.pathname.slice(import.meta.env.BASE_URL.length - 1) + location.search;
      idi(`/prijava?natrag=${encodeURIComponent(natrag)}`, true);
    }
  }, [ucitano, ja]);
  if (!ucitano || !ja) return <Ucitavanje />;
  return <>{children}</>;
}
