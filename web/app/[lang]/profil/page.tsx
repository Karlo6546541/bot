import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { OdjavaGumb } from '@/components/OdjavaGumb';
import { PrebaciJezik } from '@/components/PrebaciJezik';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { dohvatiProfil } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Moj profil'), robots: { index: false } };
}

function Red({ href, ik, t, mali }: { href: string; ik: number; t: string; mali?: string }) {
  return (
    <Link className="lista-red" href={href}>
      <Ikona k={ik} />
      <span className="t">{t}{mali && <small>{mali}</small>}</span>
      <span className="strelica"><Ikona k={IK.chevronRight} /></span>
    </Link>
  );
}

export default async function Profil({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, '/profil')}`);
  const p = await dohvatiProfil(sb, data.user.id);
  return (
    <>
      <Traka naslov={t('Profil')} />
      <Link className="profil-glava" href={put(j, `/korisnik/${data.user.id}`)}>
        <span className="avatar">{(p?.ime ?? '?').slice(0, 1).toUpperCase()}</span>
        <span>
          <b>{p?.ime ?? t('Korisnik')}</b>
          <span className="pomoc">{t('Javni profil')}</span>
        </span>
      </Link>
      <h2 className="lista-zaglavlje">{t('Oglasi')}</h2>
      <Red href={put(j, '/favoriti')} ik={IK.favoriteBorder} t={t('Spremljeni oglasi')} />
      <Red href={put(j, '/moji-oglasi')} ik={IK.sellOutlined} t={t('Moji oglasi')} />
      <h2 className="lista-zaglavlje">{t('Račun')}</h2>
      <Red href={put(j, '/profil/postavke')} ik={IK.settingsOutlined} t={t('Postavke')} />
      {p?.admin && <Red href={put(j, '/admin')} ik={IK.verified} t={t('Moderacija')} />}
      <Red href={put(j, '/uvjeti')} ik={IK.descriptionOutlined} t={t('Pravne informacije')} />
      <div className="lista-red" style={{ cursor: 'default' }}>
        <Ikona k={IK.apps} />
        <span className="t">{t('Jezik')}</span>
        <PrebaciJezik />
      </div>
      <OdjavaGumb />
    </>
  );
}
