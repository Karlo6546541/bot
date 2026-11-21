import type { Metadata } from 'next';
import { PrijavaForma } from '@/components/AuthForme';
import { sigurnoNatrag } from '@/lib/korisnik';

export const metadata: Metadata = { title: 'Prijava', robots: { index: false } };

export default async function Prijava({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  return <PrijavaForma natrag={sigurnoNatrag(sp.natrag)} greska={sp.greska} />;
}
