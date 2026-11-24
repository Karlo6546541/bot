import type { Metadata } from 'next';
import Link from 'next/link';
import { PravnaStranica } from '@/components/PravnaStranica';
import { KONTAKT_EMAIL } from '@/lib/config';
import { alternative, jezik, prevedi, prevodilac, put } from '@/lib/i18n';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const j = jezik((await params).lang);
  return { title: prevedi(j, 'Kontakt'), alternates: alternative(j, '/kontakt') };
}

export default async function Kontakt({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  return (
    <PravnaStranica naslov={t('Kontakt')}>
      {KONTAKT_EMAIL && <p>{t('Pitanja, prijave i zahtjevi u vezi s podacima:')} <a href={`mailto:${KONTAKT_EMAIL}`}>{KONTAKT_EMAIL}</a></p>}
      <p>{t('Sumnjiv oglas najbrže prijaviš gumbom "Prijavi oglas" na samom oglasu.')} <Link href={put(j, '/uvjeti')}>{t('Uvjeti korištenja')}</Link></p>
      <p>{t('Prodavatelju se javljaš porukom na njegovom oglasu.')}</p>
    </PravnaStranica>
  );
}
