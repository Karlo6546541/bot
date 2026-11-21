'use client';
import { useEffect, useRef, type ReactNode } from 'react';

/** Okvir filtera: na mobitelu zatvoren (popis je prvi), na računalu otvoren kao bočna traka. */
export function FilterDetails({ children, otvoren }: { children: ReactNode; otvoren: boolean }) {
  const ref = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    if (window.matchMedia('(min-width: 900px)').matches && ref.current) ref.current.open = true;
  }, []);
  return (
    <details ref={ref} className="ploca filteri" open={otvoren}>
      {children}
    </details>
  );
}
