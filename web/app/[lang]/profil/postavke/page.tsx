import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { ProfilForma } from '@/components/ProfilForma';
import { jezik, prevedi, put } from '@/lib/i18n';
import { dohvatiProfil } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Postavke'), robots: { index: false } };
}

export default async function Postavke({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, '/profil/postavke')}`);
  const [p, t] = await Promise.all([dohvatiProfil(sb, data.user.id), sb.from('oglasnik_privatno').select('telefon').eq('id', data.user.id).maybeSingle()]);
  return <ProfilForma id={data.user.id} ime={p?.ime ?? ''} grad={p?.grad ?? ''} drzava={p?.drzava ?? 'HR'} telefon={(t.data as { telefon: string | null } | null)?.telefon ?? ''} admin={!!p?.admin} />;
}
