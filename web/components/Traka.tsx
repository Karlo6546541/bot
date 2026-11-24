'use client';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';

/** AppBar: gumb natrag, naslov i dodatne radnje (kao u aplikaciji). natrag je adresa bez jezika. */
export function Traka({ naslov, natrag, children, h1 = true }: { naslov?: string; natrag?: string; children?: ReactNode; h1?: boolean }) {
  const { t, put } = useJezik();
  return (
    <header className="traka">
      {natrag && (
        <Link className="ikona-gumb" href={put(natrag)} aria-label={t('Natrag')}>
          <Ikona k={IK.back} />
        </Link>
      )}
      {naslov ? h1 ? <h1>{naslov}</h1> : <div className="naslov">{naslov}</div> : <div style={{ flex: 1 }} />}
      {children}
    </header>
  );
}
