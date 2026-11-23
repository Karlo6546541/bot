'use client';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { osigurajProfil, porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { useJezik } from './Jezik';

// Prikazuje se tek kad je Google prijava uključena (NEXT_PUBLIC_GOOGLE_PRIJAVA=1).
const GOOGLE_UKLJUCEN = process.env.NEXT_PUBLIC_GOOGLE_PRIJAVA === '1';
// Ako je postavljen Client ID, koristi se "Sign in with Google": prozor prikazuje tvoju domenu i naziv aplikacije,
// a ne Supabaseovu adresu. Bez njega radi staro preusmjeravanje.
const CLIENT_ID = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID || '';

interface GoogleId {
  accounts: {
    id: {
      initialize(o: Record<string, unknown>): void;
      renderButton(el: HTMLElement, o: Record<string, unknown>): void;
    };
  };
}
declare global {
  interface Window {
    google?: GoogleId;
  }
}

let skripta: Promise<void> | null = null;
function ucitajGoogle(): Promise<void> {
  if (window.google?.accounts?.id) return Promise.resolve();
  skripta ??= new Promise<void>((resolve, reject) => {
    const s = document.createElement('script');
    s.src = 'https://accounts.google.com/gsi/client';
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => {
      skripta = null;
      reject(new Error('gsi'));
    };
    document.head.appendChild(s);
  });
  return skripta;
}

async function sha256hex(s: string) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

/** Službeni Google "G" logo (boje prema Googleovim smjernicama za gumb prijave). */
function GoogleLogo() {
  return (
    <svg width="20" height="20" viewBox="0 0 48 48" aria-hidden="true" focusable="false">
      <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
      <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
      <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
    </svg>
  );
}

export function GoogleGumb({ natrag }: { natrag: string }) {
  const { j, t } = useJezik();
  const router = useRouter();
  const [greska, setGreska] = useState('');
  const [radi, setRadi] = useState(false);
  const [rezerva, setRezerva] = useState(!CLIENT_ID);
  const okvir = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!GOOGLE_UKLJUCEN || !CLIENT_ID) return;
    let ziv = true;
    (async () => {
      try {
        await ucitajGoogle();
        if (!ziv || !okvir.current || !window.google) return;
        // Nonce štiti od ponovne uporabe tokena: Googleu ide hash, Supabaseu izvorna vrijednost.
        const nonce = `${crypto.randomUUID()}${crypto.randomUUID()}`;
        const hash = await sha256hex(nonce);
        window.google.accounts.id.initialize({
          client_id: CLIENT_ID,
          nonce: hash,
          ux_mode: 'popup',
          use_fedcm_for_prompt: true,
          callback: async (odgovor: { credential?: string }) => {
            if (!odgovor.credential) return;
            setRadi(true);
            setGreska('');
            const sb = klijentPreglednika();
            const { data, error } = await sb.auth.signInWithIdToken({ provider: 'google', token: odgovor.credential, nonce });
            if (error || !data.user) {
              setRadi(false);
              return setGreska(porukaGreske(error?.message, j));
            }
            await osigurajProfil(sb, data.user);
            router.push(natrag);
            router.refresh();
          },
        });
        const tamno = window.matchMedia('(prefers-color-scheme: dark)').matches;
        window.google.accounts.id.renderButton(okvir.current, {
          type: 'standard',
          theme: tamno ? 'filled_black' : 'outline',
          size: 'large',
          text: 'continue_with',
          shape: 'rectangular',
          logo_alignment: 'left',
          width: Math.min(400, Math.max(200, okvir.current.clientWidth)),
          locale: j,
        });
        // Ako se gumb ne iscrta (blokirana ili neispravna skripta), prikaži rezervni gumb.
        setTimeout(() => { if (ziv && okvir.current && okvir.current.childElementCount === 0) setRezerva(true); }, 2000);
      } catch {
        if (ziv) setRezerva(true); // skripta blokirana (npr. blokator): staro preusmjeravanje
      }
    })();
    return () => {
      ziv = false;
    };
  }, [j, natrag, router]);

  if (!GOOGLE_UKLJUCEN) return null;
  return (
    <>
      {!rezerva && <div ref={okvir} className="google-okvir" aria-busy={radi} />}
      {rezerva && (
        <button
          className="google-gumb"
          type="button"
          disabled={radi}
          onClick={async () => {
            setGreska('');
            setRadi(true);
            const { error } = await klijentPreglednika().auth.signInWithOAuth({
              provider: 'google',
              options: { redirectTo: `${location.origin}/auth/callback?natrag=${encodeURIComponent(natrag)}` },
            });
            if (error) {
              setRadi(false);
              setGreska(porukaGreske(error.message, j));
            }
          }}
        >
          <GoogleLogo />
          <span>{radi ? t('Preusmjeravam na Google…') : t('Nastavi s Googleom')}</span>
        </button>
      )}
      {radi && !rezerva && <p className="pomoc" style={{ textAlign: 'center', marginTop: 8 }}>{t('Prijavljujem…')}</p>}
      {greska && <div className="greska" style={{ marginTop: 8 }}>{greska}</div>}
      <div className="razdjel-ili">{t('ili e-mailom')}</div>
    </>
  );
}
