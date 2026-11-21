'use client';
import { useState } from 'react';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';

export function GoogleGumb({ natrag }: { natrag: string }) {
  const [greska, setGreska] = useState('');
  return (
    <>
      <button
        className="gumb sirok"
        type="button"
        onClick={async () => {
          setGreska('');
          const { error } = await klijentPreglednika().auth.signInWithOAuth({
            provider: 'google',
            options: { redirectTo: `${location.origin}/auth/callback?natrag=${encodeURIComponent(natrag)}` },
          });
          if (error) setGreska(porukaGreske(error.message));
        }}
      >
        Nastavi s Googleom
      </button>
      {greska && <div className="greska" style={{ marginTop: 8 }}>{greska}</div>}
      <p className="pomoc" style={{ textAlign: 'center' }}>ili e-mailom</p>
    </>
  );
}
