import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { ProfilForma } from '@/components/ProfilForma';
import { dohvatiProfil } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

export const metadata: Metadata = { title: 'Postavke', robots: { index: false } };

export default async function Postavke() {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect('/prijava?natrag=/profil/postavke');
  const p = await dohvatiProfil(sb, data.user.id);
  const t = await sb.from('oglasnik_privatno').select('telefon').eq('id', data.user.id).maybeSingle();
  return <ProfilForma id={data.user.id} ime={p?.ime ?? ''} grad={p?.grad ?? ''} drzava={p?.drzava ?? 'HR'} telefon={(t.data as { telefon: string | null } | null)?.telefon ?? ''} admin={!!p?.admin} />;
}
