'use client';
import Link from 'next/link';
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { IK } from '@/lib/ikone';
import { podkategorija, jedninaNa } from '@/lib/kategorije';
import { prijedloziKategorija } from '@/lib/prijedlozi';
import { putOglasa } from '@/lib/seo';
import { klijentPreglednika } from '@/lib/supabase';
import { cijenaTekst, rijeciUpita } from '@/lib/tekst';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';
import { Slika } from './Slika';

const KLJUC = 'subhasto:nedavne-pretrage';
const MAX_NEDAVNIH = 8;

function citaj(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(KLJUC) ?? '[]');
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string').slice(0, MAX_NEDAVNIH) : [];
  } catch {
    return [];
  }
}
function pisi(lista: string[]) {
  try {
    localStorage.setItem(KLJUC, JSON.stringify(lista));
  } catch {
    /* privatni prozor ili blokirana pohrana: pretraga radi i bez povijesti */
  }
}

interface Prijedlog {
  id: string;
  naslov: string;
  kategorija: string;
  cijena: number | null;
  slike_male: string[];
}

/** Pametna pretraga: dok tipkaš, odmah nudi kategorije i oglase; prazna pretraga prikazuje nedavno traženo. */
export function PametnaPretraga({ pocetni, children }: { pocetni: string; children: ReactNode }) {
  const { j, t, put } = useJezik();
  const [q, setQ] = useState(pocetni);
  const [nedavno, setNedavno] = useState<string[]>([]);
  const [oglasi, setOglasi] = useState<Prijedlog[]>([]);
  const [ucitava, setUcitava] = useState(false);
  const brojac = useRef(0);
  const rijeci = rijeciUpita(q);
  const kategorije = useMemo(() => prijedloziKategorija(q, j), [q, j]);

  useEffect(() => setNedavno(citaj()), []);

  useEffect(() => {
    const id = ++brojac.current;
    if (!rijeciUpita(q).length) {
      setOglasi([]);
      setUcitava(false);
      return;
    }
    setUcitava(true);
    const h = setTimeout(async () => {
      try {
        let upit = klijentPreglednika()
          .from('oglasnik_oglasi')
          .select('id,naslov,kategorija,cijena,slike_male')
          .eq('status', 'aktivan')
          .gt('istjece', new Date().toISOString());
        for (const w of rijeciUpita(q)) upit = upit.like('pretraga', `%${w}%`);
        const r = await upit.order('objavljeno', { ascending: false }).limit(6);
        if (id === brojac.current) setOglasi((r.data ?? []) as unknown as Prijedlog[]);
      } catch {
        if (id === brojac.current) setOglasi([]);
      } finally {
        if (id === brojac.current) setUcitava(false);
      }
    }, 180);
    return () => clearTimeout(h);
  }, [q]);

  const zapamti = (v: string) => {
    const s = v.trim();
    if (!s) return;
    const nova = [s, ...citaj().filter((x) => x.toLowerCase() !== s.toLowerCase())].slice(0, MAX_NEDAVNIH);
    pisi(nova);
    setNedavno(nova);
  };
  const ukloni = (v: string) => {
    const nova = citaj().filter((x) => x !== v);
    pisi(nova);
    setNedavno(nova);
  };
  const upit = (v: string) => `${put('/oglasi')}?q=${encodeURIComponent(v)}`;

  return (
    <>
      <div className="trazi-traka">
        <Link className="ikona-gumb" href={put('/')} aria-label={t('Natrag')}><Ikona k={IK.back} /></Link>
        <form action={put('/oglasi')} method="get" role="search" onSubmit={() => zapamti(q)}>
          <div className="trazi-polje">
            <label className="sr-only" htmlFor="q">{t('Pretraži oglase')}</label>
            <input id="q" type="search" name="q" value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('Pretraži oglase')} enterKeyHint="search" autoFocus autoComplete="off" autoCapitalize="off" spellCheck={false} />
            {q && (
              <button type="button" className="ikona-gumb" aria-label={t('Obriši')} style={{ width: 36, height: 36 }} onClick={() => setQ('')}><Ikona k={IK.close} /></button>
            )}
            <button type="submit" className="ikona-gumb" aria-label={t('Traži')} style={{ width: 40, height: 40 }}><Ikona k={IK.search} /></button>
          </div>
        </form>
      </div>
      <h1 className="sr-only">{t('Pretraga oglasa')}</h1>
      {rijeci.length === 0 ? (
        <>
          {nedavno.length > 0 && (
            <section aria-label={t('Nedavne pretrage')}>
              <div className="lista-zaglavlje zaglavlje-red">
                <span>{t('Nedavne pretrage')}</span>
                <button type="button" className="veza-gumb" onClick={() => { pisi([]); setNedavno([]); }}>{t('Obriši sve')}</button>
              </div>
              {nedavno.map((v) => (
                <div key={v} className="prijedlog-red">
                  <Link className="lista-red" href={upit(v)} onClick={() => zapamti(v)}>
                    <Ikona k={IK.search} />
                    <span className="t">{v}</span>
                  </Link>
                  <button type="button" className="ikona-gumb" aria-label={`${t('Ukloni')}: ${v}`} onClick={() => ukloni(v)}><Ikona k={IK.close} /></button>
                </div>
              ))}
            </section>
          )}
          {children}
        </>
      ) : (
        <section aria-label={t('Prijedlozi')} aria-busy={ucitava}>
          <Link className="lista-red prijedlog-trazi" href={upit(q.trim())} onClick={() => zapamti(q)}>
            <Ikona k={IK.search} />
            <span className="t">{t('Traži „{q}”', { q: q.trim() })}</span>
            <Ikona k={IK.chevronRight} />
          </Link>
          {kategorije.length > 0 && (
            <>
              <h2 className="lista-zaglavlje">{t('Kategorije')}</h2>
              {kategorije.map((k) => (
                <Link key={k.slug} className="lista-red" href={put(`/kategorija/${k.sekcija}/${k.slug}`)} onClick={() => zapamti(q)}>
                  <span className="emoji-kat" aria-hidden="true">{k.emoji}</span>
                  <span className="t">{k.naziv}<small>{t('Pregledaj kategoriju')}</small></span>
                  <Ikona k={IK.chevronRight} />
                </Link>
              ))}
            </>
          )}
          {oglasi.length > 0 && (
            <>
              <h2 className="lista-zaglavlje">{t('Oglasi')}</h2>
              {oglasi.map((o) => {
                const kat = podkategorija(o.kategorija);
                return (
                  <Link key={o.id} className="lista-red prijedlog-oglas" href={put(putOglasa(o))} onClick={() => zapamti(q)}>
                    <span className="mala-slika">{o.slike_male[0] ? <Slika src={o.slike_male[0]} alt="" sizes="48px" /> : <span aria-hidden="true">{kat?.emoji ?? '📦'}</span>}</span>
                    <span className="t">{o.naslov}<small>{kat ? jedninaNa(kat, j) : t('Oglas')} · {cijenaTekst(o.cijena, j)}</small></span>
                  </Link>
                );
              })}
              <Link className="lista-red veza-svi" href={upit(q.trim())} onClick={() => zapamti(q)}>
                <span className="t">{t('Prikaži sve rezultate')}</span>
                <Ikona k={IK.chevronRight} />
              </Link>
            </>
          )}
          {!ucitava && oglasi.length === 0 && kategorije.length === 0 && <p className="pomoc" style={{ padding: '8px 16px' }}>{t('Nema prijedloga. Pritisni „Traži” za pretragu svih oglasa.')}</p>}
        </section>
      )}
    </>
  );
}
