'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import { IK } from '@/lib/ikone';
import { bezJezika } from '@/lib/i18n';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';
import { PrebaciJezik } from './PrebaciJezik';

const STAVKE = [
  { href: '/', naziv: 'Početna', ik: IK.homeOutlined, ikA: IK.home },
  { href: '/kategorije', naziv: 'Kategorije', ik: IK.gridOutlined, ikA: IK.grid },
  { href: '/objavi', naziv: 'Prodaj', ik: IK.addCircleOutline, ikA: IK.addCircle },
  { href: '/poruke', naziv: 'Poruke', ik: IK.chatOutline, ikA: IK.chat },
  { href: '/profil', naziv: 'Profil', ik: IK.personOutline, ikA: IK.person },
];
const KORIJENSKE = new Set(['/', '/kategorije', '/objavi', '/poruke', '/profil']);

/** Okvir kao u aplikaciji: donja traka (mobitel) ili bočna (od 840 px), donja samo na glavnim ekranima. */
export function Ljuska({ children }: { children: ReactNode }) {
  const { t, put } = useJezik();
  const sirovi = bezJezika(usePathname() || '/');
  const korijen = KORIJENSKE.has(sirovi) || sirovi.startsWith('/kategorije/');
  const aktivna = (h: string) => (h === '/' ? sirovi === '/' : sirovi === h || sirovi.startsWith(`${h}/`));
  const veze = (nav: 'dock' | 'rail') =>
    STAVKE.map((s) => {
      const a = aktivna(s.href);
      return (
        <Link key={s.href} href={put(s.href)} className={nav === 'rail' ? 'st' : undefined} aria-current={a ? 'page' : undefined} prefetch={false}>
          <Ikona k={a ? s.ikA : s.ik} />
          <span className="t">{t(s.naziv)}</span>
        </Link>
      );
    });
  return (
    <div className="app s-trakom">
      <nav className="rail" aria-label={t('Glavna navigacija')}>
        <Link className="logo" href={put('/')}>Subhasto</Link>
        {veze('rail')}
        <div style={{ marginTop: 'auto' }}><PrebaciJezik /></div>
      </nav>
      <div className={`sadrzaj ${korijen ? 's-dockom' : ''}`}>{children}</div>
      {korijen && (
        <nav className="dock" aria-label={t('Glavna navigacija')}>
          <div className="dock-red">{veze('dock')}</div>
        </nav>
      )}
    </div>
  );
}
