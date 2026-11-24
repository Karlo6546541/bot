'use client';
import Link from 'next/link';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';

export function NijePronadeno() {
  const { t, put } = useJezik();
  return (
    <div className="prazno">
      <div className="krug"><Ikona k={IK.search} /></div>
      <h1 style={{ fontSize: 20 }}>{t('Stranica nije pronađena')}</h1>
      <p>{t('Oglas je možda obrisan ili je adresa pogrešna.')}</p>
      <Link className="gumb glavni" href={put('/oglasi')}>{t('Pogledaj oglase')}</Link>
    </div>
  );
}
