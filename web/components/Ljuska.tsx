'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import { imaBazu } from '@/lib/config';
import { IK } from '@/lib/ikone';
import { klijentPreglednika } from '@/lib/supabase';
import { Ikona } from './Ikona';

const STAVKE = [
  { href: '/', naziv: 'Početna', ik: IK.homeOutlined, ikA: IK.home },
  { href: '/kategorije', naziv: 'Kategorije', ik: IK.gridOutlined, ikA: IK.grid },
  { href: '/objavi', naziv: 'Prodaj', ik: IK.addCircleOutline, ikA: IK.addCircle },
  { href: '/poruke', naziv: 'Poruke', ik: IK.chatOutline, ikA: IK.chat },
  { href: '/profil', naziv: 'Profil', ik: IK.personOutline, ikA: IK.person },
];
const KORIJENSKE = new Set(['/', '/kategorije', '/objavi', '/poruke', '/profil']);

/** Okvir kao u aplikaciji: donja traka (mobitel) ili bočna (od 840 px), prikazana samo na glavnim ekranima. */
export function Ljuska({ children }: { children: ReactNode }) {
  const put = usePathname() || '/';
  const [, forceri] = useState(0);
  useEffect(() => {
    if (!imaBazu()) return;
    const { data } = klijentPreglednika().auth.onAuthStateChange(() => forceri((n) => n + 1));
    return () => data.subscription.unsubscribe();
  }, []);
  const korijen = KORIJENSKE.has(put);
  const aktivna = (h: string) => (h === '/' ? put === '/' : put === h || put.startsWith(`${h}/`));
  const veze = (nav: 'dock' | 'rail') =>
    STAVKE.map((s) => {
      const a = aktivna(s.href);
      return (
        <Link key={s.href} href={s.href} className={nav === 'rail' ? 'st' : undefined} aria-current={a ? 'page' : undefined}>
          <Ikona k={a ? s.ikA : s.ik} />
          <span className="t">{s.naziv}</span>
        </Link>
      );
    });
  return (
    <div className="app s-trakom">
      <nav className="rail" aria-label="Glavna navigacija">
        <Link className="logo" href="/">Subhasto</Link>
        {veze('rail')}
      </nav>
      <div className={`sadrzaj ${korijen ? 's-dockom' : ''}`}>{children}</div>
      {korijen && (
        <nav className="dock" aria-label="Glavna navigacija">
          <div className="dock-red">{veze('dock')}</div>
        </nav>
      )}
    </div>
  );
}
