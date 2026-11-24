import type { ReactNode } from 'react';
import { Traka } from './Traka';

export function PravnaStranica({ naslov, children }: { naslov: string; children: ReactNode }) {
  return (
    <>
      <Traka naslov={naslov} natrag="/profil" h1={false} />
      <article className="pravno">
        <h1 className="sr-only">{naslov}</h1>
        {children}
      </article>
    </>
  );
}
