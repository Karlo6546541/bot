import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
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
      <h1>Favoriti</h1>
      {oglasi.length === 0 ? <div className="prazno ploca">Još nisi spremio nijedan oglas. Dodirni ♡ Spremi na oglasu.</div> : <MrezaOglasa oglasi={oglasi} />}
    </>
  );
}
