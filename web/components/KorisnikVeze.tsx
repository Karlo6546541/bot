'use client';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { imaBazu } from '@/lib/config';
import { klijentPreglednika } from '@/lib/supabase';

/** Veze u zaglavlju ovise o prijavi; učitavaju se u pregledniku pa javne stranice ostaju keširane. */
export function KorisnikVeze() {
  const [prijavljen, setPrijavljen] = useState<boolean | null>(null);
  useEffect(() => {
    if (!imaBazu()) return setPrijavljen(false);
    const sb = klijentPreglednika();
    sb.auth.getSession().then(({ data }) => setPrijavljen(!!data.session));
    const { data } = sb.auth.onAuthStateChange((_e, s) => setPrijavljen(!!s));
    return () => data.subscription.unsubscribe();
  }, []);
  if (prijavljen === null) return <span style={{ width: 40 }} />;
  if (!prijavljen) return <Link className="gumb malen" href="/prijava">Prijava</Link>;
  return (
    <nav aria-label="Račun">
      <Link className="ikona-gumb" href="/favoriti" aria-label="Favoriti" title="Favoriti">♡</Link>
      <Link className="ikona-gumb" href="/poruke" aria-label="Poruke" title="Poruke">✉️</Link>
      <Link className="ikona-gumb" href="/moji-oglasi" aria-label="Moji oglasi" title="Moji oglasi">📋</Link>
      <Link className="ikona-gumb" href="/profil" aria-label="Moj profil" title="Profil">👤</Link>
    </nav>
  );
}
