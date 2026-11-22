import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { MrezaOglasa } from '@/components/Kartice';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { favoritiOglasi } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Spremljeni oglasi'), robots: { index: false } };
}

export default async function Favoriti({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, '/favoriti')}`);
  const oglasi = await favoritiOglasi(sb, data.user.id);
  return (
    <>
      <Traka naslov={t('Spremljeni oglasi')} natrag="/profil" />
      {oglasi.length === 0 ? (
        <div className="prazno"><div className="krug"><Ikona k={IK.favoriteBorder} /></div><b>{t('Nema spremljenih oglasa')}</b><p>{t('Dodirni "Spremi" na oglasu da ga spremiš.')}</p></div>
      ) : <MrezaOglasa oglasi={oglasi} jezik={j} />}
    </>
  );
}
