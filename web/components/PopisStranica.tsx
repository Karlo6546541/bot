import Link from 'next/link';
import { PO_STRANICI } from '@/lib/config';
import { KATEGORIJE, STANJA, kategorija } from '@/lib/kategorije';
import { lokacijaTekst, nazivDrzave } from '@/lib/lokacije';
import type { OglasKartica, Stranica } from '@/lib/oglasi';
import { upitIzFiltera } from '@/lib/pretraga';
import type { Filteri } from '@/lib/types';
import { FilterDetails } from './FilterDetails';
import { LokacijaPolja } from './LokacijaPolja';
import { MrezaOglasa } from './Kartice';
import { Paginacija } from './Paginacija';

/** Popis oglasa s filterima. Filteri su obična GET forma: rade i bez JavaScripta. */
export function PopisStranica(props: {
  naslov: string;
  osnova: string;
  filteri: Filteri;
  stranica: number;
  rezultat: Stranica<OglasKartica>;
  kategorijaSlug?: string;
  bazaSpojena: boolean;
}) {
  const { filteri: f, stranica, rezultat, osnova } = props;
  const kat = kategorija(props.kategorijaSlug ?? f.kategorija);
  const ukupnoStranica = Math.max(1, Math.ceil(rezultat.ukupno / PO_STRANICI));
  const adresa = (s: number) => `${osnova}${upitIzFiltera(f, s)}`;
  const aktivniFilteri = [
    f.q && `„${f.q}”`,
    f.drzava && nazivDrzave(f.drzava),
    f.zupanija,
    f.grad,
    f.stanje,
    (f.cijenaOd != null || f.cijenaDo != null) && `${f.cijenaOd ?? 0} – ${f.cijenaDo ?? '∞'} €`,
  ].filter(Boolean);
  return (
    <>
      <nav className="mrvice" aria-label="Putanja">
        <Link href="/">Početna</Link> › {kat ? <><Link href="/oglasi">Oglasi</Link> › {kat.naziv}</> : 'Oglasi'}
      </nav>
      <h1>{props.naslov}</h1>
      {kat && <p className="pomoc">{kat.opis}</p>}
      <div className="popis-raspored">
        <FilterDetails otvoren={aktivniFilteri.length > 0}>
          <summary>Pretraga i filteri</summary>
          <form method="get" action={osnova} style={{ marginTop: 12 }}>
            <label className="polje">
              <span>Pojam</span>
              <input type="search" name="q" defaultValue={f.q ?? ''} placeholder="npr. Charizard, kovanica 1 kuna" />
            </label>
            {!props.kategorijaSlug && (
              <label className="polje">
                <span>Kategorija</span>
                <select name="kategorija" defaultValue={f.kategorija ?? ''}>
                  <option value="">Sve kategorije</option>
                  {KATEGORIJE.map((k) => (
                    <option key={k.slug} value={k.slug}>{k.naziv}</option>
                  ))}
                </select>
              </label>
            )}
            <fieldset className="polje">
              <legend>Cijena (€)</legend>
              <div className="dva-stupca">
                <input type="number" name="od" inputMode="decimal" min={0} placeholder="od" aria-label="Cijena od" defaultValue={f.cijenaOd ?? ''} />
                <input type="number" name="do" inputMode="decimal" min={0} placeholder="do" aria-label="Cijena do" defaultValue={f.cijenaDo ?? ''} />
              </div>
            </fieldset>
            <LokacijaPolja filter drzava={f.drzava ?? ''} zupanija={f.zupanija ?? ''} grad={f.grad ?? ''} />
            <label className="polje">
              <span>Stanje</span>
              <select name="stanje" defaultValue={f.stanje ?? ''}>
                <option value="">Bilo koje</option>
                {STANJA.map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
            </label>
            {kat?.polja.map((p) => (
              <label className="polje" key={p.kljuc}>
                <span>{p.naziv}</span>
                {p.tip === 'izbor' ? (
                  <select name={`p_${p.kljuc}`} defaultValue={f.polja?.[p.kljuc] ?? ''}>
                    <option value="">Bilo koje</option>
                    {p.opcije.map((o) => (
                      <option key={o}>{o}</option>
                    ))}
                  </select>
                ) : (
                  <input type={p.tip === 'broj' ? 'number' : 'text'} name={`p_${p.kljuc}`} defaultValue={f.polja?.[p.kljuc] ?? ''} />
                )}
              </label>
            ))}
            <label className="polje">
              <span>Poredak</span>
              <select name="sort" defaultValue={f.sort ?? 'najnovije'}>
                <option value="najnovije">Najnovije</option>
                <option value="cijena_rastuce">Cijena: od najniže</option>
                <option value="cijena_padajuce">Cijena: od najviše</option>
              </select>
            </label>
            <div className="gumbi">
              <button className="gumb glavni" type="submit">Primijeni</button>
              <Link className="gumb" href={osnova}>Očisti</Link>
            </div>
          </form>
        </FilterDetails>
        <section>
          <p className="pomoc" data-ukupno={rezultat.ukupno}>
            {rezultat.ukupno} {rezultat.ukupno === 1 ? 'oglas' : 'oglasa'}
            {aktivniFilteri.length > 0 && <> · {aktivniFilteri.join(' · ')}</>}
          </p>
          {!props.bazaSpojena && <div className="greska">Baza oglasa trenutno nije spojena.</div>}
          {rezultat.stavke.length > 0 ? (
            <MrezaOglasa oglasi={rezultat.stavke} />
          ) : (
            <div className="prazno ploca">
              <p>Nema oglasa za ovu pretragu.</p>
              <p className="pomoc">Probaj s manje filtera ili drugom riječi.</p>
            </div>
          )}
          <Paginacija stranica={stranica} ukupnoStranica={ukupnoStranica} adresa={adresa} />
        </section>
      </div>
    </>
  );
}

export { lokacijaTekst };
