import Link from 'next/link';
import type { ReactNode } from 'react';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';

/** AppBar: gumb natrag, naslov i dodatne radnje (kao u aplikaciji). */
export function Traka({ naslov, natrag, children, h1 = true }: { naslov?: string; natrag?: string; children?: ReactNode; h1?: boolean }) {
  return (
    <header className="traka">
      {natrag && (
        <Link className="ikona-gumb" href={natrag} aria-label="Natrag">
          <Ikona k={IK.back} />
        </Link>
      )}
      {naslov ? h1 ? <h1>{naslov}</h1> : <div className="naslov">{naslov}</div> : <div style={{ flex: 1 }} />}
      {children}
    </header>
  );
}
