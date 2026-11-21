import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { OdjavaGumb } from '@/components/OdjavaGumb';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { dohvatiProfil } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';

export const metadata: Metadata = { title: 'Moj profil', robots: { index: false } };

function Red({ href, ik, t, mali }: { href: string; ik: number; t: string; mali?: string }) {
  return (
    <Link className="lista-red" href={href}>
      <Ikona k={ik} />
      <span className="t">{t}{mali && <small>{mali}</small>}</span>
      <span className="strelica"><Ikona k={IK.chevronRight} /></span>
    </Link>
  );
}

export default async function Profil() {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect('/prijava?natrag=/profil');
  const p = await dohvatiProfil(sb, data.user.id);
  return (
    <>
      <Traka naslov="Profil" />
      <Link className="profil-glava" href={`/korisnik/${data.user.id}`}>
        <span className="avatar">{(p?.ime ?? '?').slice(0, 1).toUpperCase()}</span>
        <span>
          <b>{p?.ime ?? 'Korisnik'}</b>
          <span className="pomoc">Javni profil</span>
        </span>
      </Link>
      <h2 className="lista-zaglavlje">Oglasi</h2>
      <Red href="/favoriti" ik={IK.favoriteBorder} t="Spremljeni oglasi" />
      <Red href="/moji-oglasi" ik={IK.sellOutlined} t="Moji oglasi" />
      <h2 className="lista-zaglavlje">Račun</h2>
      <Red href="/profil/postavke" ik={IK.settingsOutlined} t="Postavke" />
      {p?.admin && <Red href="/admin" ik={IK.verified} t="Moderacija" />}
      <Red href="/uvjeti" ik={IK.descriptionOutlined} t="Pravne informacije" />
      <OdjavaGumb />
    </>
  );
}
