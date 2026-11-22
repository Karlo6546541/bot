import Link from 'next/link';
import { PO_STRANICI } from '@/lib/config';
import { IK } from '@/lib/ikone';
import { prevodilac, put, type Jezik } from '@/lib/i18n';
import { SEKCIJE, STANJA, nazivNa, poljaKategorije, podkategorija, sekcija } from '@/lib/kategorije';
import { lokacijaTekst, nazivDrzave } from '@/lib/lokacije';
import type { OglasKartica, Stranica } from '@/lib/oglasi';
import { upitIzFiltera } from '@/lib/pretraga';
import type { Filteri } from '@/lib/types';
import { FilterDetails } from './FilterDetails';
import { Ikona } from './Ikona';
import { LokacijaPolja } from './LokacijaPolja';
import { MrezaOglasa } from './Kartice';
import { Paginacija } from './Paginacija';
import { Traka } from './Traka';

/** Popis oglasa s filterima. Filteri su obična GET forma: rade i bez JavaScripta. osnova i natrag su adrese bez jezika. */
export function PopisStranica(props: {
  jezik: Jezik;
  naslov: string;
  osnova: string;
  filteri: Filteri;
  stranica: number;
  rezultat: Stranica<OglasKartica>;
  kategorijaSlug?: string;
  sekcijaSlug?: string;
  natrag?: string;
  bazaSpojena: boolean;
  greska?: boolean;
}) {
  const { jezik: j, filteri: f, stranica, rezultat } = props;
  const t = prevodilac(j);
  const osnova = put(j, props.osnova);
  const kat = podkategorija(props.kategorijaSlug ?? f.kategorija);
  const sek = sekcija(props.sekcijaSlug);
  const polja = poljaKategorije(kat?.slug);
  const ukupnoStranica = Math.max(1, Math.ceil(rezultat.ukupno / PO_STRANICI));
  const adresa = (s: number) => `${osnova}${upitIzFiltera(f, s)}`;
  const aktivniFilteri = [
    f.q && `„${f.q}”`,
    f.drzava && nazivDrzave(f.drzava, j),
    f.zupanija,
    f.grad,
    f.stanje && t(f.stanje),
    (f.cijenaOd != null || f.cijenaDo != null) && `${f.cijenaOd ?? 0} – ${f.cijenaDo ?? '∞'} €`,
  ].filter(Boolean);
  return (
    <>
      <Traka naslov={props.naslov} natrag={props.natrag ?? '/'}>
        <Link className="ikona-gumb" href={put(j, `/trazi${f.q ? `?q=${encodeURIComponent(f.q)}` : ''}`)} aria-label={t('Pretraži')}>
          <Ikona k={IK.search} />
        </Link>
      </Traka>
      {sek && !kat && (
        <nav className="cipovi" aria-label={t('Podkategorije')}>
          {sek.podkategorije.map((p) => (
            <Link key={p.slug} className="cip" href={put(j, `/kategorija/${sek.slug}/${p.slug}`)}>{nazivNa(p, j)}</Link>
          ))}
        </nav>
      )}
      <div className="popis-raspored">
        <FilterDetails otvoren={aktivniFilteri.length > 0}>
          <summary><Ikona k={IK.tune} /> {t('Pretraga i filteri')}</summary>
          <form method="get" action={osnova} style={{ marginTop: 12 }}>
            <label className="polje">
              <span>{t('Pojam')}</span>
              <input type="search" name="q" defaultValue={f.q ?? ''} placeholder={t('npr. Charizard, kovanica 1 kuna')} />
            </label>
            {!props.kategorijaSlug && !props.sekcijaSlug && (
              <label className="polje">
                <span>{t('Kategorija')}</span>
                <select name="kategorija" defaultValue={f.kategorija ?? ''}>
                  <option value="">{t('Sve kategorije')}</option>
                  {SEKCIJE.map((sk) => (
                    <optgroup key={sk.slug} label={nazivNa(sk, j)}>
                      {sk.podkategorije.map((k) => (
                        <option key={k.slug} value={k.slug}>{nazivNa(k, j)}</option>
                      ))}
                    </optgroup>
                  ))}
                </select>
              </label>
            )}
            <fieldset className="polje">
              <legend>{t('Cijena (€)')}</legend>
              <div className="dva-stupca">
                <input type="number" name="od" inputMode="decimal" min={0} placeholder={t('od')} aria-label={t('Cijena od')} defaultValue={f.cijenaOd ?? ''} />
                <input type="number" name="do" inputMode="decimal" min={0} placeholder={t('do')} aria-label={t('Cijena do')} defaultValue={f.cijenaDo ?? ''} />
              </div>
            </fieldset>
            <LokacijaPolja filter drzava={f.drzava ?? ''} zupanija={f.zupanija ?? ''} grad={f.grad ?? ''} />
            <label className="polje">
              <span>{t('Stanje')}</span>
              <select name="stanje" defaultValue={f.stanje ?? ''}>
                <option value="">{t('Bilo koje')}</option>
                {STANJA.map((s) => (
                  <option key={s} value={s}>{t(s)}</option>
                ))}
              </select>
            </label>
            {polja.map((p) => (
              <label className="polje" key={p.kljuc}>
                <span>{t(p.naziv)}</span>
                {p.tip === 'izbor' ? (
                  <select name={`p_${p.kljuc}`} defaultValue={f.polja?.[p.kljuc] ?? ''}>
                    <option value="">{t('Bilo koje')}</option>
                    {p.opcije.map((o) => (
                      <option key={o} value={o}>{t(o)}</option>
                    ))}
                  </select>
                ) : (
                  <input type={p.tip === 'broj' ? 'number' : 'text'} name={`p_${p.kljuc}`} defaultValue={f.polja?.[p.kljuc] ?? ''} />
                )}
              </label>
            ))}
            <label className="polje">
              <span>{t('Poredak')}</span>
              <select name="sort" defaultValue={f.sort ?? 'najnovije'}>
                <option value="najnovije">{t('Najnovije')}</option>
                <option value="cijena_rastuce">{t('Cijena: od najniže')}</option>
                <option value="cijena_padajuce">{t('Cijena: od najviše')}</option>
              </select>
            </label>
            <div className="gumbi">
              <button className="gumb glavni" type="submit">{t('Primijeni')}</button>
              <Link className="gumb" href={osnova}>{t('Očisti')}</Link>
            </div>
          </form>
        </FilterDetails>
        <section>
          <p className="pomoc" style={{ padding: '0 16px' }} data-ukupno={rezultat.ukupno}>
            {t(rezultat.ukupno === 1 ? '{n} oglas' : '{n} oglasa', { n: rezultat.ukupno })}
            {aktivniFilteri.length > 0 && <> · {aktivniFilteri.join(' · ')}</>}
          </p>
          {!props.bazaSpojena && <div className="greska" style={{ margin: 16 }}>{t('Baza oglasa trenutno nije spojena.')}</div>}
          {props.greska && <div className="greska" style={{ margin: 16 }}>{t('Oglasi se trenutno ne mogu učitati. Pokušaj ponovno za nekoliko minuta.')}</div>}
          {rezultat.stavke.length > 0 ? (
            <MrezaOglasa oglasi={rezultat.stavke} jezik={j} />
          ) : (
            <div className="prazno">
              <div className="krug"><Ikona k={IK.search} /></div>
              <b>{t('Nema oglasa za ovu pretragu')}</b>
              <p>{t('Probaj s manje filtera ili drugom riječi.')}</p>
            </div>
          )}
          <Paginacija stranica={stranica} ukupnoStranica={ukupnoStranica} adresa={adresa} jezik={j} />
        </section>
      </div>
    </>
  );
}

export { lokacijaTekst };
