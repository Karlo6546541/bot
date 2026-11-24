import { useEffect, useState } from 'preact/hooks';
import { backend } from '../data';
import type { Profil } from '../data/types';

// Prijavljeni korisnik, dijeljen među stranicama.
let ja: Profil | null = null;
let ucitano = false;
const slusatelji = new Set<() => void>();
const obavijesti = () => slusatelji.forEach((cb) => cb());

export async function osvjeziKorisnika() {
  try {
    ja = await backend.trenutni();
  } catch {
    ja = null;
  }
  ucitano = true;
  obavijesti();
}
backend.naPromjenuPrijave(() => void osvjeziKorisnika());
void osvjeziKorisnika();

export function useJa() {
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((x) => x + 1);
    slusatelji.add(cb);
    // Korisnik se možda učitao prije pretplate: osvježi jednom.
    cb();
    return () => {
      slusatelji.delete(cb);
    };
  }, []);
  return { ja, ucitano };
}

// Kratke obavijesti na dnu ekrana.
type Toast = { id: number; tekst: string };
let toastovi: Toast[] = [];
const toastSlusatelji = new Set<() => void>();
export function obavijest(tekst: string) {
  const t = { id: Date.now() + Math.random(), tekst };
  toastovi = [...toastovi, t];
  toastSlusatelji.forEach((cb) => cb());
  setTimeout(() => {
    toastovi = toastovi.filter((x) => x !== t);
    toastSlusatelji.forEach((cb) => cb());
  }, 3500);
}
export function useToastovi() {
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((x) => x + 1);
    toastSlusatelji.add(cb);
    return () => {
      toastSlusatelji.delete(cb);
    };
  }, []);
  return toastovi;
}

/** Učitavanje podataka s ponovnim pokretanjem kad se promijene ovisnosti. */
export function useUcitaj<T>(fn: () => Promise<T>, ovisnosti: unknown[]) {
  const [s, set] = useState<{ podaci?: T; greska?: string; ucitava: boolean }>({ ucitava: true });
  const [broj, setBroj] = useState(0);
  useEffect(() => {
    let ziv = true;
    set((x) => ({ ...x, ucitava: true }));
    fn().then(
      (podaci) => ziv && set({ podaci, ucitava: false }),
      (e: Error) => ziv && set({ greska: e.message || 'Greška pri učitavanju.', ucitava: false }),
    );
    return () => {
      ziv = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...ovisnosti, broj]);
  return { ...s, ponovno: () => setBroj((x) => x + 1) };
}
