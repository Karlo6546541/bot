import { MAX_SLIKA } from './config';
import { STANJA, kategorija } from './kategorije';
import { provjeriLokaciju } from './lokacije';
import type { NacrtOglasa } from './types';

/** Greške po polju obrasca ({} = sve je u redu). */
export function provjeriOglas(n: NacrtOglasa, brojSlika: number): Record<string, string> {
  const g: Record<string, string> = {};
  const naslov = n.naslov.trim();
  if (naslov.length < 3) g.naslov = 'Naslov mora imati barem 3 znaka.';
  else if (naslov.length > 100) g.naslov = 'Naslov može imati najviše 100 znakova.';
  const kat = kategorija(n.kategorija);
  if (!kat) g.kategorija = 'Odaberi kategoriju.';
  if (n.opis.trim().length < 10) g.opis = 'Opis mora imati barem 10 znakova.';
  else if (n.opis.length > 5000) g.opis = 'Opis može imati najviše 5000 znakova.';
  if (n.cijena != null && (!Number.isFinite(n.cijena) || n.cijena < 0 || n.cijena > 10_000_000)) {
    g.cijena = 'Upiši ispravnu cijenu u eurima ili odaberi "Dogovor".';
  }
  Object.assign(g, provjeriLokaciju({ drzava: n.drzava, zupanija: n.zupanija ?? '', grad: n.grad }));
  if (!(STANJA as readonly string[]).includes(n.stanje)) g.stanje = 'Odaberi stanje.';
  if (brojSlika < 1) g.slike = 'Dodaj barem jednu fotografiju.';
  else if (brojSlika > MAX_SLIKA) g.slike = `Najviše ${MAX_SLIKA} fotografija.`;
  for (const p of kat?.polja ?? []) {
    const v = (n.polja[p.kljuc] ?? '').trim();
    if (!v) continue;
    if (p.tip === 'izbor' && !p.opcije.includes(v)) g[`p_${p.kljuc}`] = 'Odaberi s popisa.';
    if (p.tip === 'broj') {
      const x = Number(v);
      if (!Number.isInteger(x) || (p.min != null && x < p.min) || (p.max != null && x > p.max)) {
        g[`p_${p.kljuc}`] = 'Upiši ispravan broj.';
      }
    }
    if (p.tip === 'tekst' && v.length > 80) g[`p_${p.kljuc}`] = 'Najviše 80 znakova.';
  }
  return g;
}

/** Nacrt očišćen za spremanje: samo polja iz kategorije, bez praznih; županija samo u Hrvatskoj ili kao regija. */
export function ocistiNacrt(n: NacrtOglasa): NacrtOglasa {
  const kat = kategorija(n.kategorija);
  const polja: Record<string, string> = {};
  for (const p of kat?.polja ?? []) {
    const v = (n.polja[p.kljuc] ?? '').trim();
    if (v) polja[p.kljuc] = v;
  }
  const zup = (n.zupanija ?? '').trim();
  return {
    ...n,
    naslov: n.naslov.trim(),
    opis: n.opis.trim(),
    grad: n.grad.trim(),
    zupanija: zup || null,
    cijena: n.cijena == null ? null : Math.round(n.cijena * 100) / 100,
    polja,
  };
}
