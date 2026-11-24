'use client';
import Link from 'next/link';
import { useJezik } from './Jezik';
import { PrebaciJezik } from './PrebaciJezik';

export function PravneVeze() {
  const { t, put } = useJezik();
  return (
    <p className="pomoc podnozje-veze">
      <Link href={put('/uvjeti')}>{t('Uvjeti korištenja')}</Link>
      <Link href={put('/privatnost')}>{t('Privatnost')}</Link>
      <Link href={put('/kontakt')}>{t('Kontakt')}</Link>
      <PrebaciJezik className="" />
    </p>
  );
}
