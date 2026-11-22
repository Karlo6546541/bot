// Država, županija i grad. Država se sprema kao ISO kod (HR, BA…), županija
// je obavezna samo u Hrvatskoj, a drugdje je slobodna "regija" ili prazno.

export const DRZAVE = [
  { kod: 'HR', naziv: 'Hrvatska', nazivEn: 'Croatia' },
  { kod: 'BA', naziv: 'Bosna i Hercegovina', nazivEn: 'Bosnia and Herzegovina' },
  { kod: 'RS', naziv: 'Srbija', nazivEn: 'Serbia' },
  { kod: 'SI', naziv: 'Slovenija', nazivEn: 'Slovenia' },
  { kod: 'ME', naziv: 'Crna Gora', nazivEn: 'Montenegro' },
  { kod: 'MK', naziv: 'Sjeverna Makedonija', nazivEn: 'North Macedonia' },
  { kod: 'AT', naziv: 'Austrija', nazivEn: 'Austria' },
  { kod: 'DE', naziv: 'Njemačka', nazivEn: 'Germany' },
  { kod: 'IT', naziv: 'Italija', nazivEn: 'Italy' },
  { kod: 'HU', naziv: 'Mađarska', nazivEn: 'Hungary' },
  { kod: 'XX', naziv: 'Druga država', nazivEn: 'Other country' },
] as const;

export const ZADANA_DRZAVA = 'HR';

export const ZUPANIJE_HR = [
  'Grad Zagreb',
  'Zagrebačka',
  'Krapinsko-zagorska',
  'Sisačko-moslavačka',
  'Karlovačka',
  'Varaždinska',
  'Koprivničko-križevačka',
  'Bjelovarsko-bilogorska',
  'Primorsko-goranska',
  'Ličko-senjska',
  'Virovitičko-podravska',
  'Požeško-slavonska',
  'Brodsko-posavska',
  'Zadarska',
  'Osječko-baranjska',
  'Šibensko-kninska',
  'Vukovarsko-srijemska',
  'Splitsko-dalmatinska',
  'Istarska',
  'Dubrovačko-neretvanska',
  'Međimurska',
];

export const nazivDrzave = (kod: string | null | undefined, j: 'hr' | 'en' = 'hr') => {
  const d = DRZAVE.find((x) => x.kod === kod);
  return d ? (j === 'en' ? d.nazivEn : d.naziv) : (kod ?? '');
};
export const jeDrzava = (kod: string | undefined): kod is string => !!kod && DRZAVE.some((d) => d.kod === kod);
export const imaZupanije = (drzava: string) => drzava === 'HR';

export interface Lokacija {
  drzava: string;
  zupanija: string | null;
  grad: string;
}

/** "Zagreb, Grad Zagreb, Hrvatska" (županija se izostavlja kad je nema). */
export function lokacijaTekst(l: Lokacija, saDrzavom = true, j: 'hr' | 'en' = 'hr'): string {
  return [l.grad, l.zupanija, saDrzavom ? nazivDrzave(l.drzava, j) : ''].filter(Boolean).join(', ');
}

/** Greške lokacije po polju ({} = u redu). */
export function provjeriLokaciju(l: { drzava: string; zupanija: string; grad: string }): Record<string, string> {
  const g: Record<string, string> = {};
  if (!jeDrzava(l.drzava)) g.drzava = 'Odaberi državu.';
  if (imaZupanije(l.drzava)) {
    if (!ZUPANIJE_HR.includes(l.zupanija)) g.zupanija = 'Odaberi županiju.';
  } else if (l.zupanija.trim() && (l.zupanija.trim().length < 2 || l.zupanija.trim().length > 60)) {
    g.zupanija = 'Regija može imati 2 do 60 znakova.';
  }
  const grad = l.grad.trim();
  if (grad.length < 2) g.grad = 'Upiši grad ili mjesto.';
  else if (grad.length > 60) g.grad = 'Najviše 60 znakova.';
  return g;
}
