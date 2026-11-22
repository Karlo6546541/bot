'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { osigurajProfil, porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { GoogleGumb } from './GoogleGumb';
import { useJezik } from './Jezik';
import { Traka } from './Traka';

export function PrijavaForma({ natrag, greska: pocetnaGreska }: { natrag: string; greska?: string }) {
  const router = useRouter();
  const { j, t, put } = useJezik();
  const [email, setEmail] = useState('');
  const [lozinka, setLozinka] = useState('');
  const [greska, setGreska] = useState(pocetnaGreska ? porukaGreske(pocetnaGreska, j) : '');
  const [radi, setRadi] = useState(false);
  return (
    <>
      <Traka natrag="/" />
      <div className="prijava">
        <div className="logo-velik">Subhasto</div>
        <h1>{t('Prijava')}</h1>
        <p className="pomoc" style={{ marginBottom: 16 }}>{t('Prijavi se da objaviš oglas, spremiš favorite i pišeš prodavateljima.')}</p>
        <GoogleGumb natrag={natrag} />
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setRadi(true);
            setGreska('');
            const sb = klijentPreglednika();
            const { data, error } = await sb.auth.signInWithPassword({ email: email.trim(), password: lozinka });
            if (error || !data.user) {
              setGreska(porukaGreske(error?.message, j));
              setRadi(false);
              return;
            }
            await osigurajProfil(sb, data.user);
            router.push(natrag);
            router.refresh();
          }}
        >
          <label className="polje"><span>{t('E-mail')}</span>
            <input type="email" name="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <label className="polje"><span>{t('Lozinka')}</span>
            <input type="password" name="lozinka" autoComplete="current-password" required value={lozinka} onChange={(e) => setLozinka(e.target.value)} />
          </label>
          {greska && <div className="greska" role="alert">{greska}</div>}
          <button className="gumb glavni sirok" type="submit" disabled={radi}>{radi ? t('Prijavljujem…') : t('Prijavi se')}</button>
        </form>
        <p style={{ textAlign: 'center', marginTop: 16 }}>{t('Nemaš račun?')} <Link href={`${put('/registracija')}?natrag=${encodeURIComponent(natrag)}`}>{t('Registriraj se')}</Link></p>
      </div>
    </>
  );
}

export function RegistracijaForma({ natrag }: { natrag: string }) {
  const router = useRouter();
  const { j, t, put } = useJezik();
  const [ime, setIme] = useState('');
  const [email, setEmail] = useState('');
  const [lozinka, setLozinka] = useState('');
  const [uvjeti, setUvjeti] = useState(false);
  const [greska, setGreska] = useState('');
  const [radi, setRadi] = useState(false);
  const [potvrda, setPotvrda] = useState(false);
  if (potvrda) {
    return (
      <>
        <Traka natrag="/prijava" />
        <div className="prijava">
          <h1>{t('Provjeri e-mail')}</h1>
          <p>{t('Poslali smo poveznicu na {email}. Klikni je da potvrdiš račun, a zatim se prijavi.', { email })}</p>
          <Link className="gumb" href={put('/prijava')}>{t('Na prijavu')}</Link>
        </div>
      </>
    );
  }
  return (
    <>
      <Traka natrag="/prijava" />
      <div className="prijava">
        <div className="logo-velik">Subhasto</div>
        <h1>{t('Registracija')}</h1>
        <GoogleGumb natrag={natrag} />
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            if (!uvjeti) return setGreska(t('Za registraciju prihvati Uvjete korištenja.'));
            if (lozinka.length < 8) return setGreska(t('Lozinka mora imati barem 8 znakova.'));
            setRadi(true);
            setGreska('');
            const sb = klijentPreglednika();
            const { data, error } = await sb.auth.signUp({
              email: email.trim(),
              password: lozinka,
              options: { data: { ime: ime.trim() }, emailRedirectTo: `${location.origin}/auth/callback?natrag=${encodeURIComponent(natrag)}` },
            });
            if (error) {
              setGreska(porukaGreske(error.message, j));
              return setRadi(false);
            }
            if (data.session && data.user) {
              await osigurajProfil(sb, data.user);
              router.push(natrag);
              router.refresh();
            } else setPotvrda(true);
          }}
        >
          <label className="polje"><span>{t('Ime ili nadimak')}</span>
            <input type="text" name="ime" autoComplete="nickname" maxLength={60} required value={ime} onChange={(e) => setIme(e.target.value)} />
          </label>
          <label className="polje"><span>{t('E-mail')}</span>
            <input type="email" name="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <label className="polje"><span>{t('Lozinka (barem 8 znakova)')}</span>
            <input type="password" name="lozinka" autoComplete="new-password" minLength={8} required value={lozinka} onChange={(e) => setLozinka(e.target.value)} />
          </label>
          <label className="kvacica">
            <input type="checkbox" name="uvjeti" checked={uvjeti} onChange={(e) => setUvjeti(e.target.checked)} />
            <span>{t('Prihvaćam')} <Link href={put('/uvjeti')}>{t('Uvjete korištenja')}</Link> {t('i')} <Link href={put('/privatnost')}>{t('Politiku privatnosti')}</Link></span>
          </label>
          {greska && <div className="greska" role="alert">{greska}</div>}
          <button className="gumb glavni sirok" type="submit" disabled={radi}>{radi ? t('Stvaram račun…') : t('Napravi račun')}</button>
        </form>
        <p style={{ textAlign: 'center', marginTop: 16 }}>{t('Već imaš račun?')} <Link href={`${put('/prijava')}?natrag=${encodeURIComponent(natrag)}`}>{t('Prijavi se')}</Link></p>
      </div>
    </>
  );
}
