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
import { useJezik } from './Jezik';
import { osvjeziStranice } from '@/lib/osvjezi';

/** Radnje vlasnika: uredi, produlji, označi prodano, obriši, tko se javio. */
export function VlasnikAkcije(props: { oglasId: string; status: string; istekao: boolean; cijena: number | null }) {
  const router = useRouter();
  const { j, t, put } = useJezik();
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
    if (error) return setPoruka(porukaGreske(error.message, j));
    setPoruka(ok);
    void osvjeziStranice(props.oglasId);
    if (nakon) nakon();
    else router.refresh();
  }
  const sb = () => klijentPreglednika();
  return (
    <div className="stog">
      {poruka && <div className="pomoc" role="status">{poruka}</div>}
      <div className="gumbi">
        {mozeUredivati && <Link className="gumb malen" href={put(`/oglas/${props.oglasId}/uredi`)}>{t('Uredi')}</Link>}
        {props.status === 'aktivan' && (
          <button className="gumb malen" type="button" disabled={radi}
            onClick={() => izvrsi(() => sb().from('oglasnik_oglasi').update({ istjece: new Date(Date.now() + ISTEK_DANA * 86400000).toISOString() }).eq('id', props.oglasId), t('Oglas je produljen za {n} dana.', { n: ISTEK_DANA }))}>
            {props.istekao ? t('Obnovi') : t('Produlji')}
          </button>
        )}
        {props.status === 'aktivan' && <button className="gumb malen" type="button" onClick={() => setProdaja(true)}>{t('Označi kao prodano')}</button>}
        <button className="gumb malen" type="button" onClick={async () => setKontakti(await kontaktiOglasa(sb(), props.oglasId))}>{t('Kontakti')}</button>
        <button className="gumb malen opasno" type="button" onClick={() => setBrisanje(true)}>{t('Obriši')}</button>
      </div>
      {prodaja && (
        <Dijalog naslov={t('Označi kao prodano')} onZatvori={() => setProdaja(false)}>
          <form onSubmit={(e) => {
            e.preventDefault();
            const c = cijena.trim() === '' ? null : Number(cijena.replace(',', '.'));
            if (c != null && (!Number.isFinite(c) || c < 0)) return setPoruka(t('Upiši ispravnu cijenu ili ostavi prazno.'));
            setProdaja(false);
            void izvrsi(() => sb().from('oglasnik_oglasi').update({ status: 'prodano', prodano_cijena: c }).eq('id', props.oglasId), t('Oglas je označen kao prodan.'));
          }}>
            <label className="polje"><span>{t('Konačna cijena u € (neobavezno)')}</span>
              <input type="number" inputMode="decimal" min={0} step="0.01" value={cijena} onChange={(e) => setCijena(e.target.value)} />
            </label>
            <p className="pomoc">{t('Cijena se ne prikazuje kupcima; služi samo tebi i statistici.')}</p>
            <div className="gumbi">
              <button className="gumb glavni" type="submit">{t('Označi prodano')}</button>
              <button className="gumb" type="button" onClick={() => setProdaja(false)}>{t('Odustani')}</button>
            </div>
          </form>
        </Dijalog>
      )}
      {brisanje && (
        <Dijalog naslov={t('Obrisati oglas?')} onZatvori={() => setBrisanje(false)}>
          <p>{t('Oglas više neće biti vidljiv. Razgovori o njemu ostaju u porukama.')}</p>
          <div className="gumbi">
            <button className="gumb opasno" type="button" onClick={() => {
              setBrisanje(false);
              void izvrsi(() => sb().from('oglasnik_oglasi').update({ status: 'obrisan' }).eq('id', props.oglasId), t('Oglas je obrisan.'), () => {
                router.push(put('/moji-oglasi'));
                router.refresh();
              });
            }}>{t('Obriši')}</button>
            <button className="gumb" type="button" onClick={() => setBrisanje(false)}>{t('Odustani')}</button>
          </div>
        </Dijalog>
      )}
      {kontakti && (
        <Dijalog naslov={t('Tko te kontaktirao')} onZatvori={() => setKontakti(null)}>
          {kontakti.length === 0 ? <p className="pomoc">{t('Još nitko nije poslao poruku ni pogledao tvoj broj.')}</p> : (
            <>
              <p>{t('{p} poruka · {tel} prikaza telefona', { p: kontakti.filter((x) => x.vrsta === 'poruka').length, tel: kontakti.filter((x) => x.vrsta === 'telefon').length })}</p>
              <ul>{kontakti.slice(0, 50).map((x) => <li key={x.id}>{x.vrsta === 'poruka' ? t('Poruka') : t('Prikaz telefona')} · {datum(x.kreirano, j)}</li>)}</ul>
            </>
          )}
          <button className="gumb" type="button" onClick={() => setKontakti(null)}>{t('Zatvori')}</button>
        </Dijalog>
      )}
    </div>
  );
}
