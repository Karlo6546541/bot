'use client';
import { useRouter } from 'next/navigation';
import { klijentPreglednika } from '@/lib/supabase';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';

export function OdjavaGumb() {
  const router = useRouter();
  return (
    <button
      type="button"
      className="lista-red"
      onClick={async () => {
        await klijentPreglednika().auth.signOut();
        router.push('/');
        router.refresh();
      }}
    >
      <Ikona k={IK.logout} />
      <span className="t">Odjavi se</span>
    </button>
  );
}
