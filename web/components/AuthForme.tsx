'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { osigurajProfil, porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { GoogleGumb } from './GoogleGumb';
import { Traka } from './Traka';

export function PrijavaForma({ natrag, greska: pocetnaGreska }: { natrag: string; greska?: string }) {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [lozinka, setLozinka] = useState('');
  const [greska, setGreska] = useState(pocetnaGreska ?? '');
  const [radi, setRadi] = useState(false);
  return (
    <>
    <Traka natrag="/" naslov="" />
    <div className="prijava">
      <div className="logo-velik">Subhasto</div>
      <h1>Prijava</h1>
      <GoogleGumb natrag={natrag} />
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setRadi(true);
          setGreska('');
          const sb = klijentPreglednika();
          const { data, error } = await sb.auth.signInWithPassword({ email: email.trim(), password: lozinka });
          if (error || !data.user) {
            setGreska(porukaGreske(error?.message));
            setRadi(false);
            return;
          }
          await osigurajProfil(sb, data.user);
          router.push(natrag);
          router.refresh();
        }}
      >
        <label className="polje"><span>E-mail</span>
          <input type="email" name="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="polje"><span>Lozinka</span>
          <input type="password" name="lozinka" autoComplete="current-password" required value={lozinka} onChange={(e) => setLozinka(e.target.value)} />
        </label>
        {greska && <div className="greska" role="alert">{greska}</div>}
        <button className="gumb glavni sirok" type="submit" disabled={radi}>{radi ? 'Prijavljujem…' : 'Prijavi se'}</button>
      </form>
      <p style={{ textAlign: 'center' }}>Nemaš račun? <Link href={`/registracija?natrag=${encodeURIComponent(natrag)}`}>Registriraj se</Link></p>
    </div>
    </>
  );
}

export function RegistracijaForma({ natrag }: { natrag: string }) {
  const router = useRouter();
  const [ime, setIme] = useState('');
  const [email, setEmail] = useState('');
  const [lozinka, setLozinka] = useState('');
  const [uvjeti, setUvjeti] = useState(false);
  const [greska, setGreska] = useState('');
  const [radi, setRadi] = useState(false);
  const [potvrda, setPotvrda] = useState(false);
  if (potvrda) {
    return (
      <div className="prijava">
        <h1>Provjeri e-mail</h1>
        <p>Poslali smo poveznicu na <b>{email}</b>. Klikni je da potvrdiš račun, a zatim se prijavi.</p>
        <Link className="gumb" href="/prijava">Na prijavu</Link>
      </div>
    );
  }
  return (
    <>
    <Traka natrag="/prijava" naslov="" />
    <div className="prijava">
      <div className="logo-velik">Subhasto</div>
      <h1>Registracija</h1>
      <GoogleGumb natrag={natrag} />
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (!uvjeti) return setGreska('Za registraciju prihvati Uvjete korištenja.');
          if (lozinka.length < 8) return setGreska('Lozinka mora imati barem 8 znakova.');
          setRadi(true);
          setGreska('');
          const sb = klijentPreglednika();
          const { data, error } = await sb.auth.signUp({
            email: email.trim(),
            password: lozinka,
            options: { data: { ime: ime.trim() }, emailRedirectTo: `${location.origin}/auth/callback?natrag=${encodeURIComponent(natrag)}` },
          });
          if (error) {
            setGreska(porukaGreske(error.message));
            return setRadi(false);
          }
          if (data.session && data.user) {
            await osigurajProfil(sb, data.user);
            router.push(natrag);
            router.refresh();
          } else setPotvrda(true);
        }}
      >
        <label className="polje"><span>Ime ili nadimak</span>
          <input type="text" name="ime" autoComplete="nickname" maxLength={60} required value={ime} onChange={(e) => setIme(e.target.value)} />
        </label>
        <label className="polje"><span>E-mail</span>
          <input type="email" name="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="polje"><span>Lozinka (barem 8 znakova)</span>
          <input type="password" name="lozinka" autoComplete="new-password" minLength={8} required value={lozinka} onChange={(e) => setLozinka(e.target.value)} />
        </label>
        <label className="kvacica">
          <input type="checkbox" name="uvjeti" checked={uvjeti} onChange={(e) => setUvjeti(e.target.checked)} />
          <span>Prihvaćam <Link href="/uvjeti">Uvjete korištenja</Link> i <Link href="/privatnost">Politiku privatnosti</Link></span>
        </label>
        {greska && <div className="greska" role="alert">{greska}</div>}
        <button className="gumb glavni sirok" type="submit" disabled={radi}>{radi ? 'Stvaram račun…' : 'Napravi račun'}</button>
      </form>
      <p style={{ textAlign: 'center' }}>Već imaš račun? <Link href={`/prijava?natrag=${encodeURIComponent(natrag)}`}>Prijavi se</Link></p>
    </div>
    </>
  );
}
