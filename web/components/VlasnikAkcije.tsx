'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { ISTEK_DANA } from '@/lib/config';
import { porukaGreske } from '@/lib/korisnik';
import { kontaktiOglasa } from '@/lib/oglasi';
import { klijentPreglednika } from '@/lib/supabase';
import { datum } from '@/lib/tekst';
import type { Kontakt } from '@/lib/types';
import { Dijalog } from './Dijalog';

/** Radnje vlasnika: uredi, produlji, označi prodano, obriši, tko se javio. */
export function VlasnikAkcije(props: {
  oglasId: string;
  status: string;
  istekao: boolean;
  cijena: number | null;
  nakon?: 'osvjezi' | 'moji';
}) {
  const router = useRouter();
  const [prodaja, setProdaja] = useState(false);
  const [brisanje, setBrisanje] = useState(false);
  const [kontakti, setKontakti] = useState<Kontakt[] | null>(null);
  const [cijena, setCijena] = useState(props.cijena != null ? String(props.cijena) : '');
  const [poruka, setPoruka] = useState('');
  const [radi, setRadi] = useState(false);
  const mozeUredivati = props.status === 'aktivan' || props.status === 'prodano';

  async function izvrsi(fn: () => PromiseLike<{ error: { message: string } | null }>, ok: string, nakon?: () => void) {
    setRadi(true);
    setPoruka('');
    const { error } = await fn();
    setRadi(false);
    if (error) return setPoruka(porukaGreske(error.message));
    setPoruka(ok);
    if (nakon) nakon();
    else router.refresh();
  }
  const sb = () => klijentPreglednika();
  return (
    <div className="stog">
      {poruka && <div className="pomoc" role="status">{poruka}</div>}
      <div className="gumbi">
        {mozeUredivati && <Link className="gumb malen" href={`/oglas/${props.oglasId}/uredi`}>✏️ Uredi</Link>}
        {props.status === 'aktivan' && (
          <button className="gumb malen" type="button" disabled={radi}
            onClick={() => izvrsi(() => sb().from('oglasnik_oglasi').update({ istjece: new Date(Date.now() + ISTEK_DANA * 86400000).toISOString() }).eq('id', props.oglasId), `Oglas je produljen za ${ISTEK_DANA} dana.`)}>
            {props.istekao ? '🔄 Obnovi' : '⏱ Produlji'}
          </button>
        )}
        {props.status === 'aktivan' && <button className="gumb malen" type="button" onClick={() => setProdaja(true)}>✅ Označi kao prodano</button>}
        <button className="gumb malen" type="button" onClick={async () => setKontakti(await kontaktiOglasa(sb(), props.oglasId))}>👥 Kontakti</button>
        <button className="gumb malen opasno" type="button" onClick={() => setBrisanje(true)}>🗑 Obriši</button>
      </div>
      {prodaja && (
        <Dijalog naslov="Označi kao prodano" onZatvori={() => setProdaja(false)}>
          <form onSubmit={(e) => {
            e.preventDefault();
            const c = cijena.trim() === '' ? null : Number(cijena.replace(',', '.'));
            if (c != null && (!Number.isFinite(c) || c < 0)) return setPoruka('Upiši ispravnu cijenu ili ostavi prazno.');
            setProdaja(false);
            void izvrsi(() => sb().from('oglasnik_oglasi').update({ status: 'prodano', prodano_cijena: c }).eq('id', props.oglasId), 'Oglas je označen kao prodan.');
          }}>
            <label className="polje"><span>Konačna cijena u € (neobavezno)</span>
              <input type="number" inputMode="decimal" min={0} step="0.01" value={cijena} onChange={(e) => setCijena(e.target.value)} />
            </label>
            <p className="pomoc">Cijena se ne prikazuje kupcima; služi samo tebi i statistici.</p>
            <div className="gumbi">
              <button className="gumb glavni" type="submit">Označi prodano</button>
              <button className="gumb" type="button" onClick={() => setProdaja(false)}>Odustani</button>
            </div>
          </form>
        </Dijalog>
      )}
      {brisanje && (
        <Dijalog naslov="Obrisati oglas?" onZatvori={() => setBrisanje(false)}>
          <p>Oglas više neće biti vidljiv. Razgovori o njemu ostaju u porukama.</p>
          <div className="gumbi">
            <button className="gumb opasno" type="button" onClick={() => {
              setBrisanje(false);
              void izvrsi(() => sb().from('oglasnik_oglasi').update({ status: 'obrisan' }).eq('id', props.oglasId), 'Oglas je obrisan.', () => {
                router.push('/moji-oglasi');
                router.refresh();
              });
            }}>Obriši</button>
            <button className="gumb" type="button" onClick={() => setBrisanje(false)}>Odustani</button>
          </div>
        </Dijalog>
      )}
      {kontakti && (
        <Dijalog naslov="Tko te kontaktirao" onZatvori={() => setKontakti(null)}>
          {kontakti.length === 0 ? <p className="pomoc">Još nitko nije poslao poruku ni pogledao tvoj broj.</p> : (
            <>
              <p>{kontakti.filter((x) => x.vrsta === 'poruka').length} poruka · {kontakti.filter((x) => x.vrsta === 'telefon').length} prikaza telefona</p>
              <ul>{kontakti.slice(0, 50).map((x) => <li key={x.id}>{x.vrsta === 'poruka' ? 'Poruka' : 'Prikaz telefona'} · {datum(x.kreirano)}</li>)}</ul>
            </>
          )}
          <button className="gumb" type="button" onClick={() => setKontakti(null)}>Zatvori</button>
        </Dijalog>
      )}
    </div>
  );
}
