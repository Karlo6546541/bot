import type { Metadata } from 'next';
import { PrijavaForma } from '@/components/AuthForme';
import { sigurnoNatrag } from '@/lib/korisnik';
import { jezik, prevedi, put } from '@/lib/i18n';

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Prijava'), robots: { index: false } };
}

export default async function Prijava({ params, searchParams }: { params: Promise<{ lang: string }>; searchParams: Promise<Record<string, string | undefined>> }) {
  const j = jezik((await params).lang);
  const sp = await searchParams;
  return <PrijavaForma natrag={sp.natrag ? sigurnoNatrag(sp.natrag) : put(j, '/')} greska={sp.greska} />;
}
