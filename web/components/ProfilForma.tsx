'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { DRZAVE } from '@/lib/lokacije';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';

export function ProfilForma(props: { id: string; ime: string; grad: string; drzava: string; telefon: string; admin: boolean }) {
  const router = useRouter();
  const [ime, setIme] = useState(props.ime);
  const [grad, setGrad] = useState(props.grad);
  const [drzava, setDrzava] = useState(props.drzava);
  const [telefon, setTelefon] = useState(props.telefon);
  const [poruka, setPoruka] = useState('');
  const [radi, setRadi] = useState(false);
  return (
    <div style={{ maxWidth: 480 }} className="stog">
      <h1>Moj profil</h1>
      <form className="ploca" onSubmit={async (e) => {
        e.preventDefault();
        if (ime.trim().length < 2) return setPoruka('Upiši ime.');
        setRadi(true);
        const sb = klijentPreglednika();
        const a = await sb.from('oglasnik_profili').update({ ime: ime.trim(), grad: grad.trim() || null, drzava }).eq('id', props.id);
        const b = await sb.from('oglasnik_privatno').upsert({ id: props.id, telefon: telefon.trim() || null });
        setRadi(false);
        const err = a.error ?? b.error;
        setPoruka(err ? porukaGreske(err.message) : 'Profil je spremljen.');
        router.refresh();
      }}>
        <label className="polje"><span>Ime ili nadimak (vidljivo drugima)</span><input type="text" maxLength={60} value={ime} onChange={(e) => setIme(e.target.value)} /></label>
        <label className="polje"><span>Država</span>
          <select value={drzava} onChange={(e) => setDrzava(e.target.value)}>{DRZAVE.map((d) => <option key={d.kod} value={d.kod}>{d.naziv}</option>)}</select>
        </label>
        <label className="polje"><span>Grad</span><input type="text" maxLength={60} value={grad} onChange={(e) => setGrad(e.target.value)} /></label>
        <label className="polje"><span>Telefon (prikazuje se samo na oglasima gdje to odabereš)</span><input type="tel" maxLength={30} value={telefon} onChange={(e) => setTelefon(e.target.value)} /></label>
        {poruka && <div className="pomoc" role="status">{poruka}</div>}
        <button className="gumb glavni" type="submit" disabled={radi}>Spremi</button>
      </form>
      <div className="gumbi">
        <Link className="gumb" href={`/korisnik/${props.id}`}>Moj javni profil</Link>
        {props.admin && <Link className="gumb" href="/admin">Moderacija</Link>}
        <button className="gumb opasno" type="button" onClick={async () => { await klijentPreglednika().auth.signOut(); router.push('/'); router.refresh(); }}>Odjava</button>
      </div>
    </div>
  );
}
