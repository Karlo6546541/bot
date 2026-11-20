import { useEffect, useState } from 'preact/hooks';

// Čiste adrese (/oglas/…, /kategorija/…) s podrškom za podmapu (/bot/).
const BAZA = import.meta.env.BASE_URL.replace(/\/$/, '');

export const adresa = (put: string) => BAZA + (put.startsWith('/') ? put : `/${put}`);

function trenutniPut() {
  let p = location.pathname;
  if (BAZA && p.startsWith(BAZA)) p = p.slice(BAZA.length);
  return { put: p || '/', upit: new URLSearchParams(location.search) };
}

const slusatelji = new Set<() => void>();
export function idi(put: string, zamijeni = false) {
  const url = adresa(put);
  if (url === location.pathname + location.search) return;
  if (zamijeni) history.replaceState(null, '', url);
  else history.pushState(null, '', url);
  window.scrollTo(0, 0);
  slusatelji.forEach((cb) => cb());
}
window.addEventListener('popstate', () => slusatelji.forEach((cb) => cb()));

export function useRuta() {
  const [r, setR] = useState(trenutniPut);
  useEffect(() => {
    const cb = () => setR(trenutniPut());
    slusatelji.add(cb);
    return () => {
      slusatelji.delete(cb);
    };
  }, []);
  return r;
}

/** Klik na <a href="/bot/…"> unutar aplikacije ne učitava stranicu ponovno. */
export function presretniPoveznice() {
  document.addEventListener('click', (e) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const a = (e.target as Element).closest?.('a');
    if (!a || a.target || a.hasAttribute('download')) return;
    const href = a.getAttribute('href');
    if (!href || !href.startsWith(BAZA + '/') && href !== BAZA) return;
    e.preventDefault();
    const u = new URL(a.href);
    idi(u.pathname.slice(BAZA.length) + u.search);
  });
}
