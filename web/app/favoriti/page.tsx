import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { MrezaOglasa } from '@/components/Kartice';
import { favoritiOglasi } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

export const metadata: Metadata = { title: 'Favoriti', robots: { index: false } };

export default async function Favoriti() {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect('/prijava?natrag=/favoriti');
  const oglasi = await favoritiOglasi(sb, data.user.id);
  return (
    <>
      <Traka naslov="Spremljeni oglasi" natrag="/profil" />
      {oglasi.length === 0 ? <div className="prazno"><div className="krug"><Ikona k={IK.favoriteBorder} /></div><b>Nema spremljenih oglasa</b><p>Dodirni srce na oglasu da ga spremiš.</p></div> : <MrezaOglasa oglasi={oglasi} />}
    </>
  );
}
