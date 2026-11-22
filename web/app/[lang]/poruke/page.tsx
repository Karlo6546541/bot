import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { Slika } from '@/components/Slika';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { razgovori } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';
import { prije } from '@/lib/tekst';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Poruke'), robots: { index: false } };
}

export default async function Poruke({ params }: { params: P }) {
  const j = jezik((await params).lang);
  const t = prevodilac(j);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, '/poruke')}`);
  const lista = await razgovori(sb, data.user.id);
  return (
    <>
      <Traka naslov={t('Poruke')} />
      {lista.length === 0 && (
        <div className="prazno">
          <div className="krug"><Ikona k={IK.chatOutline} /></div>
          <b>{t('Još nemaš poruka')}</b>
          <p>{t('Kad nekome pišeš o oglasu ili netko piše tebi, razgovor će biti ovdje.')}</p>
        </div>
      )}
      {lista.map((s) => (
        <Link className="redak" key={s.razgovor.id} href={put(j, `/poruke/${s.razgovor.id}`)} style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="slicica" style={{ position: 'relative' }}>{s.oglas?.slike_male[0] && <Slika src={s.oglas.slike_male[0]} alt="" sizes="56px" />}</div>
          <div className="tijelo">
            <div className="naslov">{s.neprocitano && <span className="oznaka crvena">{t('Novo')}</span>} {s.oglas?.naslov ?? t('Obrisan oglas')}</div>
            <div className="pomoc">{s.sugovornik?.ime ?? t('Korisnik')} · {s.zadnja ? prije(s.zadnja.poslano, Date.now(), j) : ''}</div>
            <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{s.zadnja?.tekst}</div>
          </div>
        </Link>
      ))}
    </>
  );
}
