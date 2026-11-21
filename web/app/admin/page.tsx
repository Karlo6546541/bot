import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { Traka } from '@/components/Traka';
import { AdminPlocha } from '@/components/AdminPlocha';
import { dohvatiProfil, korisniciZaAdmina, prijaveZaAdmina } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

export const metadata: Metadata = { title: 'Moderacija', robots: { index: false } };

export default async function Admin() {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect('/prijava?natrag=/admin');
  const ja = await dohvatiProfil(sb, data.user.id);
  if (!ja?.admin) return <div className="prazno ploca">Ova stranica je samo za administratore.</div>;
  const [prijave, korisnici] = await Promise.all([prijaveZaAdmina(sb), korisniciZaAdmina(sb)]);
  return (
    <>
      <Traka naslov="Moderacija" natrag="/profil" />
      <div className="stranica"><AdminPlocha jaId={data.user.id} prijave={prijave} korisnici={korisnici} /></div>
    </>
  );
}
