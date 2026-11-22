'use client';
import { createContext, useContext, type ReactNode } from 'react';
import { prevodilac, put as putNa, type Jezik } from '@/lib/i18n';

const Kontekst = createContext<Jezik>('hr');

export function JezikProvider({ jezik, children }: { jezik: Jezik; children: ReactNode }) {
  return <Kontekst.Provider value={jezik}>{children}</Kontekst.Provider>;
}

/** Jezik stranice u klijentskim komponentama: t() prevodi, put() dodaje /en kad treba. */
export function useJezik() {
  const j = useContext(Kontekst);
  return { j, t: prevodilac(j), put: (p: string) => putNa(j, p) };
}
