// Kategorije i dodatna polja po kategoriji. Novu kategoriju ili polje
// dodaješ samo ovdje: obrazac za objavu, stranica oglasa i filteri
// čitaju ovu datoteku.

export type Polje =
  | { kljuc: string; naziv: string; tip: 'izbor'; opcije: string[] }
  | { kljuc: string; naziv: string; tip: 'tekst'; placeholder?: string }
  | { kljuc: string; naziv: string; tip: 'broj'; min?: number; max?: number };

export interface Kategorija {
  slug: string;
  naziv: string;
  ikona: string;
  opis: string;
  polja: Polje[];
}

const JEZICI = ['Engleski', 'Japanski', 'Njemački', 'Hrvatski', 'Ostalo'];

export const KATEGORIJE: Kategorija[] = [
  {
    slug: 'kartice',
    naziv: 'Kartice',
    ikona: '🃏',
    opis: 'Pokémon, Yu-Gi-Oh!, Digimon, One Piece, Magic i ostale kartice',
    polja: [
      {
        kljuc: 'igra',
        naziv: 'Igra',
        tip: 'izbor',
        opcije: ['Pokémon', 'Yu-Gi-Oh!', 'Digimon', 'One Piece', 'Magic', 'Ostalo'],
      },
      { kljuc: 'set', naziv: 'Set', tip: 'tekst', placeholder: 'npr. Base Set' },
      { kljuc: 'jezik', naziv: 'Jezik', tip: 'izbor', opcije: JEZICI },
    ],
  },
  {
    slug: 'kovanice-i-novcanice',
    naziv: 'Kovanice i novčanice',
    ikona: '🪙',
    opis: 'Kovanice, novčanice i medalje',
    polja: [
      { kljuc: 'drzava', naziv: 'Država', tip: 'tekst', placeholder: 'npr. Jugoslavija' },
      { kljuc: 'godina', naziv: 'Godina', tip: 'broj', min: 1, max: 2100 },
    ],
  },
  {
    slug: 'marke',
    naziv: 'Marke',
    ikona: '📮',
    opis: 'Poštanske marke, omotnice i albumi',
    polja: [
      { kljuc: 'drzava', naziv: 'Država', tip: 'tekst' },
      { kljuc: 'godina', naziv: 'Godina', tip: 'broj', min: 1840, max: 2100 },
      { kljuc: 'zigosano', naziv: 'Žigosano', tip: 'izbor', opcije: ['Da', 'Ne'] },
    ],
  },
  {
    slug: 'stripovi-i-manga',
    naziv: 'Stripovi i manga',
    ikona: '📚',
    opis: 'Stripovi, manga i grafički romani',
    polja: [
      { kljuc: 'izdavac', naziv: 'Izdavač', tip: 'tekst' },
      { kljuc: 'broj', naziv: 'Broj izdanja', tip: 'tekst' },
      { kljuc: 'jezik', naziv: 'Jezik', tip: 'izbor', opcije: JEZICI },
    ],
  },
  {
    slug: 'figurice',
    naziv: 'Figurice',
    ikona: '🗿',
    opis: 'Akcijske figure, kipići i modeli',
    polja: [
      { kljuc: 'proizvodac', naziv: 'Proizvođač', tip: 'tekst' },
      { kljuc: 'kutija', naziv: 'Originalna kutija', tip: 'izbor', opcije: ['Da', 'Ne'] },
    ],
  },
  {
    slug: 'gramofonske-ploce',
    naziv: 'Gramofonske ploče',
    ikona: '💿',
    opis: 'LP, singlice i kolekcije ploča',
    polja: [
      { kljuc: 'izvodac', naziv: 'Izvođač', tip: 'tekst' },
      { kljuc: 'format', naziv: 'Format', tip: 'izbor', opcije: ['LP', 'Singlica (7")', 'Maxi (12")', 'Box set'] },
      { kljuc: 'godina', naziv: 'Godina izdanja', tip: 'broj', min: 1900, max: 2100 },
    ],
  },
  {
    slug: 'ostalo',
    naziv: 'Ostalo kolekcionarstvo',
    ikona: '🧭',
    opis: 'Sve ostalo što se skuplja',
    polja: [],
  },
];

/** Fiksna ljestvica stanja predmeta. */
export const STANJA = ['Novo', 'Kao novo', 'Dobro', 'Oštećeno'] as const;
export type Stanje = (typeof STANJA)[number];

export const RAZLOZI_PRIJAVE = [
  { kljuc: 'prevara', naziv: 'Prevara' },
  { kljuc: 'krivotvorina', naziv: 'Krivotvorina' },
  { kljuc: 'neprimjereno', naziv: 'Neprimjeren sadržaj' },
  { kljuc: 'ostalo', naziv: 'Ostalo' },
] as const;
export type RazlogPrijave = (typeof RAZLOZI_PRIJAVE)[number]['kljuc'];

export const kategorija = (slug: string | undefined) =>
  KATEGORIJE.find((k) => k.slug === slug);
