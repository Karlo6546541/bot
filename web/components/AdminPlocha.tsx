'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { RAZLOZI_PRIJAVE } from '@/lib/kategorije';
import { porukaGreske } from '@/lib/korisnik';
import { putOglasa } from '@/lib/seo';
import { klijentPreglednika } from '@/lib/supabase';
import { datum } from '@/lib/tekst';
import type { Prijava, Profil } from '@/lib/types';

const naziv = (k: string) => RAZLOZI_PRIJAVE.find((r) => r.kljuc === k)?.naziv ?? k;

export function AdminPlocha({ jaId, prijave, korisnici }: { jaId: string; prijave: Prijava[]; korisnici: Profil[] }) {
  const router = useRouter();
  const [tab, setTab] = useState<'prijave' | 'korisnici'>('prijave');
  const [samoOtvorene, setSamoOtvorene] = useState(true);
  const [poruka, setPoruka] = useState('');
  const sb = () => klijentPreglednika();
  async function radnja(fn: () => PromiseLike<{ error: { message: string } | null }>, ok: string) {
    const { error } = await fn();
    setPoruka(error ? porukaGreske(error.message) : ok);
    router.refresh();
  }
  const popis = prijave.filter((p) => !samoOtvorene || p.status === 'otvorena');
  return (
    <>
      <h1>Moderacija</h1>
      <div className="kartice-tabovi" role="tablist">
        <button role="tab" type="button" aria-selected={tab === 'prijave'} onClick={() => setTab('prijave')}>Prijavljeni oglasi</button>
        <button role="tab" type="button" aria-selected={tab === 'korisnici'} onClick={() => setTab('korisnici')}>Korisnici</button>
      </div>
      {poruka && <div className="pomoc" role="status">{poruka}</div>}
      {tab === 'prijave' ? (
        <>
          <label className="kvacica"><input type="checkbox" checked={samoOtvorene} onChange={(e) => setSamoOtvorene(e.target.checked)} />Samo otvorene prijave</label>
          {popis.length === 0 && <div className="prazno ploca">Nema prijava.</div>}
          {popis.map((p) => (
            <div className="redak" key={p.id} data-prijava={p.id}>
              <div className="tijelo stog">
                <div>
                  <div className="naslov">{p.oglas ? <Link href={putOglasa(p.oglas)}>{p.oglas.naslov}</Link> : 'Oglas više ne postoji'}{' '}
                    <span className={`oznaka ${p.status === 'otvorena' ? 'crvena' : 'siva'}`}>{p.status === 'otvorena' ? 'Otvorena' : 'Riješena'}</span></div>
                  <div><b>{naziv(p.razlog)}</b> · {datum(p.kreirano)}{p.oglas && ` · oglas: ${p.oglas.status}`}</div>
                  {p.napomena && <div className="opis">{p.napomena}</div>}
                </div>
                <div className="gumbi">
                  {p.oglas && p.oglas.status !== 'uklonjen' && (
                    <button className="gumb malen opasno" type="button" onClick={() => radnja(async () => {
                      const a = await sb().from('oglasnik_oglasi').update({ status: 'uklonjen', uklonjeno_razlog: naziv(p.razlog) }).eq('id', p.oglas!.id);
                      if (a.error) return a;
                      return sb().from('oglasnik_prijave').update({ status: 'rijesena' }).eq('id', p.id);
                    }, 'Oglas je uklonjen.')}>Ukloni oglas</button>
                  )}
                  {p.oglas && <button className="gumb malen opasno" type="button" onClick={() => radnja(() => sb().from('oglasnik_profili').update({ blokiran: true }).eq('id', p.oglas!.korisnik_id), 'Korisnik je blokiran.')}>Blokiraj prodavatelja</button>}
                  {p.status === 'otvorena' && <button className="gumb malen" type="button" onClick={() => radnja(() => sb().from('oglasnik_prijave').update({ status: 'rijesena' }).eq('id', p.id), 'Prijava je zatvorena.')}>Zatvori bez radnje</button>}
                </div>
              </div>
            </div>
          ))}
        </>
      ) : (
        <div className="tablica-omot">
          <table className="admin">
            <thead><tr><th>Ime</th><th>Registriran</th><th>Status</th><th /></tr></thead>
            <tbody>
              {korisnici.map((k) => (
                <tr key={k.id}>
                  <td><Link href={`/korisnik/${k.id}`}>{k.ime}</Link>{k.admin && ' (admin)'}</td>
                  <td>{datum(k.registriran)}</td>
                  <td>{k.blokiran ? <span className="oznaka crvena">Blokiran</span> : 'Aktivan'}</td>
                  <td>{k.id !== jaId && <button className={`gumb malen ${k.blokiran ? '' : 'opasno'}`} type="button" onClick={() => radnja(() => sb().from('oglasnik_profili').update({ blokiran: !k.blokiran }).eq('id', k.id), k.blokiran ? 'Blokada je skinuta.' : 'Korisnik je blokiran.')}>{k.blokiran ? 'Odblokiraj' : 'Blokiraj'}</button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
