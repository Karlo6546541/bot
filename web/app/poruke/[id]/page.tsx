import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { Traka } from '@/components/Traka';
import { RazgovorForma } from '@/components/RazgovorForma';
import { SigurnaKupnja } from '@/components/SigurnaKupnja';
import { razgovorSPorukama } from '@/lib/oglasi';
import { putOglasa } from '@/lib/seo';
import { klijentServera } from '@/lib/supabase';
import { cijenaTekst, datum } from '@/lib/tekst';

export const metadata: Metadata = { title: 'Razgovor', robots: { index: false } };

export default async function Razgovor({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect(`/prijava?natrag=/poruke/${id}`);
  const r = await razgovorSPorukama(sb, data.user.id, id);
  if (!r?.sazetak) notFound();
  const { sazetak, poruke } = r;
  const o = sazetak.oglas;
  return (
    <div style={{ maxWidth: 720, margin: '0 auto' }}>
      <Traka naslov={sazetak.sugovornik?.ime ?? 'Korisnik'} natrag="/poruke" />
      {o && (
        <Link className="redak" href={putOglasa(o)} style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="slicica">{/* eslint-disable-next-line @next/next/no-img-element */}<img src={o.slike_male[0]} alt="" /></div>
          <div className="tijelo"><div className="naslov">{o.naslov}</div><div>{cijenaTekst(o.cijena)}</div>{o.status !== 'aktivan' && <div className="pomoc">Oglas više nije aktivan.</div>}</div>
        </Link>
      )}
      <RazgovorForma razgovorId={id} uid={data.user.id} neprocitano={sazetak.neprocitano}
        poruke={poruke.map((p) => ({ id: p.id, moja: p.posiljatelj_id === data.user!.id, tekst: p.tekst, vrijeme: `${datum(p.poslano)} ${new Date(p.poslano).toLocaleTimeString('hr-HR', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Zagreb' })}` }))} />
      <SigurnaKupnja />
    </div>
  );
}
