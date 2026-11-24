import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { RazgovorForma } from '@/components/RazgovorForma';
import { SigurnaKupnja } from '@/components/SigurnaKupnja';
import { Slika } from '@/components/Slika';
import { Traka } from '@/components/Traka';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { razgovorSPorukama } from '@/lib/oglasi';
import { putOglasa } from '@/lib/seo';
import { klijentServera } from '@/lib/supabase';
import { cijenaTekst, datum } from '@/lib/tekst';

type P = Promise<{ lang: string; id: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Razgovor'), robots: { index: false } };
}

export default async function Razgovor({ params }: { params: P }) {
  const { id, lang } = await params;
  const j = jezik(lang);
  const t = prevodilac(j);
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`${put(j, '/prijava')}?natrag=${put(j, `/poruke/${id}`)}`);
  const r = await razgovorSPorukama(sb, data.user.id, id);
  if (!r?.sazetak) notFound();
  const { sazetak, poruke } = r;
  const o = sazetak.oglas;
  const vrijeme = (iso: string) => `${datum(iso, j)} ${new Date(iso).toLocaleTimeString(j === 'en' ? 'en-GB' : 'hr-HR', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Zagreb' })}`;
  return (
    <div style={{ maxWidth: 720, margin: '0 auto' }}>
      <Traka naslov={sazetak.sugovornik?.ime ?? t('Korisnik')} natrag="/poruke" />
      {o && (
        <Link className="redak" href={put(j, putOglasa(o))} style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="slicica" style={{ position: 'relative' }}><Slika src={o.slike_male[0]} alt="" sizes="56px" /></div>
          <div className="tijelo"><div className="naslov">{o.naslov}</div><div>{cijenaTekst(o.cijena, j)}</div>{o.status !== 'aktivan' && <div className="pomoc">{t('Oglas više nije aktivan.')}</div>}</div>
        </Link>
      )}
      <RazgovorForma razgovorId={id} uid={data.user.id} neprocitano={sazetak.neprocitano}
        poruke={poruke.map((p) => ({ id: p.id, moja: p.posiljatelj_id === data.user!.id, tekst: p.tekst, vrijeme: vrijeme(p.poslano) }))} />
      <div style={{ padding: '0 16px' }}><SigurnaKupnja /></div>
    </div>
  );
}
