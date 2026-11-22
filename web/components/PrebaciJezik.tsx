'use client';
import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { bezJezika, put } from '@/lib/i18n';
import { useJezik } from './Jezik';

function Veza({ className }: { className?: string }) {
  const { j } = useJezik();
  const sp = useSearchParams();
  const drugi = j === 'hr' ? 'en' : 'hr';
  const upit = sp.toString();
  const cilj = put(drugi, bezJezika(usePathname() || '/')) + (upit ? `?${upit}` : '');
  return (
    <Link className={className ?? 'jezik-gumb'} href={cilj} hrefLang={drugi} lang={drugi} prefetch={false}
      onClick={() => { try { document.cookie = `jezik=${drugi};path=/;max-age=31536000;samesite=lax`; } catch {} }}>
      {drugi === 'en' ? 'English' : 'Hrvatski'}
    </Link>
  );
}

/** Prebacivanje hrvatski ↔ engleski na istoj stranici. */
export function PrebaciJezik({ className }: { className?: string }) {
  return (
    <Suspense fallback={null}>
      <Veza className={className} />
    </Suspense>
  );
}
