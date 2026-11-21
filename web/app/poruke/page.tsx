import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Ikona } from '@/components/Ikona';
import { Traka } from '@/components/Traka';
import { IK } from '@/lib/ikone';
import { razgovori } from '@/lib/oglasi';
import { klijentServera } from '@/lib/supabase';
import { prije } from '@/lib/tekst';

export const metadata: Metadata = { title: 'Poruke', robots: { index: false } };

export default async function Poruke() {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect('/prijava?natrag=/poruke');
  const lista = await razgovori(sb, data.user.id);
  return (
    <>
      <Traka naslov="Poruke" />
      {lista.length === 0 && (
        <div className="prazno">
          <div className="krug"><Ikona k={IK.chatOutline} /></div>
          <b>Još nemaš poruka</b>
          <p>Kad nekome pišeš o oglasu ili netko piše tebi, razgovor će biti ovdje.</p>
        </div>
      )}
      {lista.map((s) => (
        <Link className="redak" key={s.razgovor.id} href={`/poruke/${s.razgovor.id}`} style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="slicica">{s.oglas?.slike_male[0] && /* eslint-disable-next-line @next/next/no-img-element */ <img src={s.oglas.slike_male[0]} alt="" loading="lazy" />}</div>
          <div className="tijelo">
            <div className="naslov">{s.neprocitano && <span className="oznaka crvena">Novo</span>} {s.oglas?.naslov ?? 'Obrisan oglas'}</div>
            <div className="pomoc">{s.sugovornik?.ime ?? 'Korisnik'} · {s.zadnja ? prije(s.zadnja.poslano) : ''}</div>
            <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{s.zadnja?.tekst}</div>
          </div>
        </Link>
      ))}
    </>
  );
}
