import Link from 'next/link';
import { PO_STRANICI } from '@/lib/config';
import { SEKCIJE, STANJA, poljaKategorije, podkategorija, sekcija } from '@/lib/kategorije';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';
import { Traka } from './Traka';
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
  sekcijaSlug?: string;
  natrag?: string;
  bazaSpojena: boolean;
}) {
  const { filteri: f, stranica, rezultat, osnova } = props;
  const kat = podkategorija(props.kategorijaSlug ?? f.kategorija);
  const sek = sekcija(props.sekcijaSlug);
  const polja = poljaKategorije(kat?.slug);
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
      <Traka naslov={props.naslov} natrag={props.natrag ?? '/'}>
        <Link className="ikona-gumb" href={`/trazi${f.q ? `?q=${encodeURIComponent(f.q)}` : ''}`} aria-label="Pretraži">
          <Ikona k={IK.search} />
        </Link>
      </Traka>
      {sek && !kat && (
        <nav className="cipovi" aria-label="Podkategorije">
          {sek.podkategorije.map((p) => (
            <Link key={p.slug} className="cip" href={`/kategorija/${sek.slug}/${p.slug}`}>{p.naziv}</Link>
          ))}
        </nav>
      )}
      <div className="popis-raspored">
        <FilterDetails otvoren={aktivniFilteri.length > 0}>
          <summary><Ikona k={IK.tune} /> Pretraga i filteri</summary>
          <form method="get" action={osnova} style={{ marginTop: 12 }}>
            <label className="polje">
              <span>Pojam</span>
              <input type="search" name="q" defaultValue={f.q ?? ''} placeholder="npr. Charizard, kovanica 1 kuna" />
            </label>
            {!props.kategorijaSlug && !props.sekcijaSlug && (
              <label className="polje">
                <span>Kategorija</span>
                <select name="kategorija" defaultValue={f.kategorija ?? ''}>
                  <option value="">Sve kategorije</option>
                  {SEKCIJE.map((sk) => (
                    <optgroup key={sk.slug} label={sk.naziv}>
                      {sk.podkategorije.map((k) => (
                        <option key={k.slug} value={k.slug}>{k.naziv}</option>
                      ))}
                    </optgroup>
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
            {polja.map((p) => (
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
          <p className="pomoc" style={{ padding: '0 16px' }} data-ukupno={rezultat.ukupno}>
            {rezultat.ukupno} {rezultat.ukupno === 1 ? 'oglas' : 'oglasa'}
            {aktivniFilteri.length > 0 && <> · {aktivniFilteri.join(' · ')}</>}
          </p>
          {!props.bazaSpojena && <div className="greska">Baza oglasa trenutno nije spojena.</div>}
          {rezultat.stavke.length > 0 ? (
            <MrezaOglasa oglasi={rezultat.stavke} />
          ) : (
            <div className="prazno">
              <div className="krug"><Ikona k={IK.search} /></div>
              <b>Nema oglasa za ovu pretragu</b>
              <p>Probaj s manje filtera ili drugom riječi.</p>
            </div>
          )}
          <Paginacija stranica={stranica} ukupnoStranica={ukupnoStranica} adresa={adresa} />
        </section>
      </div>
    </>
  );
}

export { lokacijaTekst };
