import type { Metadata } from 'next';
import { RegistracijaForma } from '@/components/AuthForme';
import { sigurnoNatrag } from '@/lib/korisnik';
import { jezik, prevedi, put } from '@/lib/i18n';

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Registracija'), robots: { index: false } };
}

export default async function Registracija({ params, searchParams }: { params: Promise<{ lang: string }>; searchParams: Promise<Record<string, string | undefined>> }) {
  const j = jezik((await params).lang);
  const sp = await searchParams;
  return <RegistracijaForma natrag={sp.natrag ? sigurnoNatrag(sp.natrag) : put(j, '/')} />;
}
