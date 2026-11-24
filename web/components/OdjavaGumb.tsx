'use client';
import { useRouter } from 'next/navigation';
import { klijentPreglednika } from '@/lib/supabase';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';

export function OdjavaGumb() {
  const router = useRouter();
  const { t, put } = useJezik();
  return (
    <button type="button" className="lista-red" onClick={async () => {
      await klijentPreglednika().auth.signOut();
      router.push(put('/'));
      router.refresh();
    }}>
      <Ikona k={IK.logout} />
      <span className="t">{t('Odjavi se')}</span>
    </button>
  );
}
