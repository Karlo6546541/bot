import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { ObjaviForma } from '@/components/ObjaviForma';
import { dohvatiOglas } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

export const metadata: Metadata = { title: 'Uredi oglas', robots: { index: false } };

export default async function Uredi({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  const o = await dohvatiOglas(sb, id);
  // Samo vlasnik uređuje (RLS to svejedno provodi); uklonjeni i obrisani oglasi se ne uređuju.
  if (!o || !data.user || o.korisnik_id !== data.user.id || o.status === 'obrisan' || o.status === 'uklonjen') notFound();
  return <ObjaviForma oglas={o} />;
}
