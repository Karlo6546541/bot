import type { Metadata } from 'next';
import { RegistracijaForma } from '@/components/AuthForme';
import { sigurnoNatrag } from '@/lib/korisnik';

export const metadata: Metadata = { title: 'Registracija', robots: { index: false } };

export default async function Registracija({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  return <RegistracijaForma natrag={sigurnoNatrag(sp.natrag)} />;
}
