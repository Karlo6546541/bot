'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { DRZAVE, nazivDrzave } from '@/lib/lokacije';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { useJezik } from './Jezik';
import { Traka } from './Traka';

export function ProfilForma(props: { id: string; ime: string; grad: string; drzava: string; telefon: string; admin: boolean }) {
  const router = useRouter();
  const { j, t, put } = useJezik();
  const [ime, setIme] = useState(props.ime);
  const [grad, setGrad] = useState(props.grad);
  const [drzava, setDrzava] = useState(props.drzava);
  const [telefon, setTelefon] = useState(props.telefon);
  const [poruka, setPoruka] = useState('');
  const [radi, setRadi] = useState(false);
  return (
    <>
      <Traka naslov={t('Postavke')} natrag="/profil" />
      <div className="stranica stog">
        <form className="ploca" onSubmit={async (e) => {
          e.preventDefault();
          if (ime.trim().length < 2) return setPoruka(t('Upiši ime.'));
          setRadi(true);
          const sb = klijentPreglednika();
          const [a, b] = await Promise.all([
            sb.from('oglasnik_profili').update({ ime: ime.trim(), grad: grad.trim() || null, drzava }).eq('id', props.id),
            sb.from('oglasnik_privatno').upsert({ id: props.id, telefon: telefon.trim() || null }),
          ]);
          setRadi(false);
          const err = a.error ?? b.error;
          setPoruka(err ? porukaGreske(err.message, j) : t('Profil je spremljen.'));
          router.refresh();
        }}>
          <label className="polje"><span>{t('Ime ili nadimak (vidljivo drugima)')}</span><input type="text" maxLength={60} value={ime} onChange={(e) => setIme(e.target.value)} /></label>
          <label className="polje"><span>{t('Država')}</span>
            <select value={drzava} onChange={(e) => setDrzava(e.target.value)}>{DRZAVE.map((d) => <option key={d.kod} value={d.kod}>{nazivDrzave(d.kod, j)}</option>)}</select>
          </label>
          <label className="polje"><span>{t('Grad')}</span><input type="text" maxLength={60} value={grad} onChange={(e) => setGrad(e.target.value)} /></label>
          <label className="polje"><span>{t('Telefon (prikazuje se samo na oglasima gdje to odabereš)')}</span><input type="tel" maxLength={30} value={telefon} onChange={(e) => setTelefon(e.target.value)} /></label>
          {poruka && <div className="pomoc" role="status">{poruka}</div>}
          <button className="gumb glavni" type="submit" disabled={radi}>{radi ? t('Spremam…') : t('Spremi')}</button>
        </form>
        <div className="gumbi">
          <Link className="gumb" href={put(`/korisnik/${props.id}`)}>{t('Moj javni profil')}</Link>
          {props.admin && <Link className="gumb" href={put('/admin')}>{t('Moderacija')}</Link>}
        </div>
      </div>
    </>
  );
}
