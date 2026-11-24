import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { AdminPlocha } from '@/components/AdminPlocha';
import { Traka } from '@/components/Traka';
import { jezik, prevedi, put } from '@/lib/i18n';
import { dohvatiProfil, korisniciZaAdmina, prijaveZaAdmina } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Moderacija'), robots: { index: false } };
}

export default async function Admin({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, '/admin')}`);
  const ja = await dohvatiProfil(sb, data.user.id);
  if (!ja?.admin) return <div className="prazno"><b>{prevedi(j, 'Ova stranica je samo za administratore.')}</b></div>;
  const [prijave, korisnici] = await Promise.all([prijaveZaAdmina(sb), korisniciZaAdmina(sb)]);
  return (
    <>
      <Traka naslov={prevedi(j, 'Moderacija')} natrag="/profil" />
      <div className="stranica"><AdminPlocha jaId={data.user.id} prijave={prijave} korisnici={korisnici} /></div>
    </>
  );
}
