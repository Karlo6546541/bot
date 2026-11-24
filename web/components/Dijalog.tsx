'use client';
import { useEffect, type ReactNode } from 'react';

export function Dijalog(props: { naslov: string; children: ReactNode; onZatvori: () => void }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === 'Escape' && props.onZatvori();
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [props]);
  return (
    <div className="zastor" onClick={(e) => e.target === e.currentTarget && props.onZatvori()}>
      <div className="dijalog" role="dialog" aria-modal="true" aria-label={props.naslov}>
        <h2>{props.naslov}</h2>
        {props.children}
      </div>
    </div>
  );
}
