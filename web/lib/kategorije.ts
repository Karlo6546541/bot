// GENERIRANO skriptom web/scripts/generiraj_kategorije.py iz Flutter koda
// (loop_app/lib/models/device.dart i widgets/category_style.dart). Ne uređuj ručno:
// promijeni Flutter kod i pokreni skriptu. Ikone su kodovi Material Icons fonta.

export type Polje =
  | { kljuc: string; naziv: string; tip: 'izbor'; opcije: string[] }
  | { kljuc: string; naziv: string; tip: 'tekst'; placeholder?: string }
  | { kljuc: string; naziv: string; tip: 'broj'; min?: number; max?: number };

export interface Podkategorija {
  slug: string;
  naziv: string;
  jednina: string;
  ikona: number;
  emoji: string;
  boja: number;
}

export interface Sekcija {
  slug: string;
  naziv: string;
  ikona: number;
  boja: number;
  polja: Polje[];
  podkategorije: Podkategorija[];
}

export const SEKCIJE: Sekcija[] = [
  {
    slug: "kartice",
    naziv: "Kartice",
    ikona: 58899,
    boja: 2,
    polja: [{ kljuc: "igra", naziv: "Igra", tip: 'izbor', opcije: ["Pokémon", "Yu-Gi-Oh!", "Digimon", "One Piece", "Magic", "Ostalo"] }, { kljuc: "set", naziv: "Set", tip: 'tekst', placeholder: "npr. Base Set" }, { kljuc: "jezik", naziv: "Jezik", tip: 'izbor', opcije: ["Engleski", "Japanski", "Njemački", "Hrvatski", "Ostalo"] }],
    podkategorije: [
    { slug: "pokemon-i-ostali-tcg", naziv: "Pokémon i ostali TCG", jednina: "TCG kartica", ikona: 57671, emoji: "⚡", boja: 0, },
    { slug: "magic-the-gathering", naziv: "Magic: The Gathering", jednina: "MTG kartica", ikona: 57531, emoji: "🧙", boja: 1, },
    { slug: "yu-gi-oh", naziv: "Yu-Gi-Oh!", jednina: "Yu-Gi-Oh! kartica", ikona: 62454, emoji: "🃏", boja: 2, },
    { slug: "sportske-kartice", naziv: "Sportske kartice", jednina: "Kartica", ikona: 58899, emoji: "🏀", boja: 3, },
    { slug: "ocijenjene-kartice", naziv: "Ocijenjene kartice", jednina: "Ocijenjena kartica", ikona: 62588, emoji: "🏅", boja: 4, }
    ],
  },
  {
    slug: "novci",
    naziv: "Novci",
    ikona: 61917,
    boja: 3,
    polja: [{ kljuc: "drzava", naziv: "Država izdanja", tip: 'tekst', placeholder: "npr. Jugoslavija" }, { kljuc: "godina", naziv: "Godina", tip: 'broj', min: 1, max: 2100 }],
    podkategorije: [
    { slug: "kovanice", naziv: "Kovanice", jednina: "Kovanica", ikona: 61917, emoji: "🪙", boja: 0, },
    { slug: "novcanice", naziv: "Novčanice", jednina: "Novčanica", ikona: 62054, emoji: "💶", boja: 1, },
    { slug: "zlato-i-srebro", naziv: "Zlato i srebro", jednina: "Zlatnik ili srebrnjak", ikona: 984737, emoji: "🥇", boja: 2, }
    ],
  },
  {
    slug: "markice",
    naziv: "Markice",
    ikona: 61835,
    boja: 4,
    polja: [{ kljuc: "drzava", naziv: "Država izdanja", tip: 'tekst' }, { kljuc: "godina", naziv: "Godina", tip: 'broj', min: 1840, max: 2100 }, { kljuc: "zigosano", naziv: "Žigosano", tip: 'izbor', opcije: ["Da", "Ne"] }],
    podkategorije: [
    { slug: "markice", naziv: "Markice", jednina: "Markica", ikona: 61835, emoji: "✉️", boja: 0, },
    { slug: "omotnice-i-filatelija", naziv: "Omotnice i filatelija", jednina: "Filatelistički predmet", ikona: 58308, emoji: "📮", boja: 1, }
    ],
  },
  {
    slug: "razglednice-i-plakati",
    naziv: "Razglednice i plakati",
    ikona: 62109,
    boja: 5,
    polja: [],
    podkategorije: [
    { slug: "razglednice", naziv: "Razglednice", jednina: "Razglednica", ikona: 62109, emoji: "🖼️", boja: 0, },
    { slug: "plakati-i-reklame", naziv: "Plakati i reklame", jednina: "Plakat", ikona: 61728, emoji: "🪧", boja: 1, }
    ],
  },
  {
    slug: "ploce-i-mediji",
    naziv: "Ploče i mediji",
    ikona: 61031,
    boja: 6,
    polja: [{ kljuc: "izvodjac", naziv: "Izvođač", tip: 'tekst' }, { kljuc: "format", naziv: "Format", tip: 'izbor', opcije: ["LP", "Singlica (7\")", "Maxi (12\")", "Box set", "CD", "Kazeta"] }, { kljuc: "godina", naziv: "Godina izdanja", tip: 'broj', min: 1900, max: 2100 }],
    podkategorije: [
    { slug: "vinil", naziv: "Vinil", jednina: "Ploča", ikona: 57462, emoji: "💿", boja: 0, },
    { slug: "cd-ovi-i-kazete", naziv: "CD-ovi i kazete", jednina: "CD ili kazeta", ikona: 61031, emoji: "📀", boja: 1, }
    ],
  },
  {
    slug: "stripovi",
    naziv: "Stripovi",
    ikona: 57535,
    boja: 7,
    polja: [{ kljuc: "izdavac", naziv: "Izdavač", tip: 'tekst' }, { kljuc: "broj", naziv: "Broj izdanja", tip: 'tekst' }, { kljuc: "jezik", naziv: "Jezik", tip: 'izbor', opcije: ["Engleski", "Japanski", "Njemački", "Hrvatski", "Ostalo"] }],
    podkategorije: [
    { slug: "stripovi-i-manga", naziv: "Stripovi i manga", jednina: "Strip", ikona: 57535, emoji: "📚", boja: 0, },
    { slug: "jugoslavenski-stripovi", naziv: "Jugoslavenski stripovi", jednina: "Strip", ikona: 61890, emoji: "📖", boja: 1, }
    ],
  },
  {
    slug: "figure-i-igracke",
    naziv: "Figure i igračke",
    ikona: 62376,
    boja: 0,
    polja: [{ kljuc: "proizvodjac", naziv: "Proizvođač", tip: 'tekst' }, { kljuc: "kutija", naziv: "Originalna kutija", tip: 'izbor', opcije: ["Da", "Ne"] }],
    podkategorije: [
    { slug: "figure-i-funko", naziv: "Figure i Funko", jednina: "Figura", ikona: 62376, emoji: "🧸", boja: 0, },
    { slug: "modeli-i-lego", naziv: "Modeli i LEGO", jednina: "Model", ikona: 57936, emoji: "🧱", boja: 1, }
    ],
  },
  {
    slug: "konzole-i-igre",
    naziv: "Konzole i igre",
    ikona: 58856,
    boja: 1,
    polja: [],
    podkategorije: [
    { slug: "konzole", naziv: "Konzole", jednina: "Konzola", ikona: 58856, emoji: "🎮", boja: 0, },
    { slug: "videoigre", naziv: "Videoigre", jednina: "Videoigra", ikona: 59050, emoji: "🕹️", boja: 1, },
    { slug: "retro-racunala", naziv: "Retro računala", jednina: "Retro računalo", ikona: 57733, emoji: "🖥️", boja: 2, }
    ],
  },
  {
    slug: "memorabilije-i-autogrami",
    naziv: "Memorabilije i autogrami",
    ikona: 61466,
    boja: 2,
    polja: [],
    podkategorije: [
    { slug: "sportske-memorabilije", naziv: "Sportske memorabilije", jednina: "Memorabilija", ikona: 61466, emoji: "🏆", boja: 0, },
    { slug: "autogrami", naziv: "Autogrami", jednina: "Autogram", ikona: 984557, emoji: "✍️", boja: 1, }
    ],
  },
  {
    slug: "vojna-i-povijest",
    naziv: "Vojna i povijest",
    ikona: 61901,
    boja: 3,
    polja: [],
    podkategorije: [
    { slug: "vojna-i-povijesna-oprema", naziv: "Vojna i povijesna oprema", jednina: "Povijesni predmet", ikona: 61901, emoji: "🎖️", boja: 0, },
    { slug: "znacke-i-medalje", naziv: "Značke i medalje", jednina: "Značka", ikona: 61901, emoji: "🎖️", boja: 1, }
    ],
  },
  {
    slug: "slike-i-umjetnost",
    naziv: "Slike i umjetnost",
    ikona: 62031,
    boja: 4,
    polja: [],
    podkategorije: [
    { slug: "slike-i-crtezi", naziv: "Slike i crteži", jednina: "Slika", ikona: 62031, emoji: "🎨", boja: 0, },
    { slug: "grafike-i-fotografije", naziv: "Grafike i fotografije", jednina: "Grafika", ikona: 62110, emoji: "🖼️", boja: 1, }
    ],
  },
  {
    slug: "satovi",
    naziv: "Satovi",
    ikona: 62642,
    boja: 5,
    polja: [],
    podkategorije: [
    { slug: "rucni-satovi", naziv: "Ručni satovi", jednina: "Sat", ikona: 62641, emoji: "🕰️", boja: 0, },
    { slug: "dzepni-i-zidni-satovi", naziv: "Džepni i zidni satovi", jednina: "Sat", ikona: 58710, emoji: "🕰️", boja: 1, }
    ],
  },
  {
    slug: "antikviteti-i-vintage",
    naziv: "Antikviteti i vintage",
    ikona: 58147,
    boja: 6,
    polja: [],
    podkategorije: [
    { slug: "vintage-i-antikviteti", naziv: "Vintage i antikviteti", jednina: "Vintage", ikona: 58147, emoji: "🏺", boja: 0, },
    { slug: "keramika-i-porculan", naziv: "Keramika i porculan", jednina: "Keramika", ikona: 57720, emoji: "🍶", boja: 1, },
    { slug: "stari-nakit", naziv: "Stari nakit", jednina: "Nakit", ikona: 984551, emoji: "💍", boja: 2, }
    ],
  },
  {
    slug: "elektronika",
    naziv: "Elektronika",
    ikona: 57803,
    boja: 7,
    polja: [],
    podkategorije: [
    { slug: "ostala-elektronika", naziv: "Ostala elektronika", jednina: "Elektronika", ikona: 57804, emoji: "🔌", boja: 0, },
    { slug: "mobiteli", naziv: "Mobiteli", jednina: "Mobitel", ikona: 58822, emoji: "📱", boja: 1, },
    { slug: "racunala-i-laptopi", naziv: "Računala i laptopi", jednina: "Računalo", ikona: 58217, emoji: "💻", boja: 2, },
    { slug: "kamere-i-foto", naziv: "Kamere i foto", jednina: "Kamera", ikona: 58550, emoji: "📷", boja: 3, },
    { slug: "audio-i-slusalice", naziv: "Audio i slušalice", jednina: "Audio", ikona: 58111, emoji: "🎧", boja: 4, }
    ],
  }
];

export const PODKATEGORIJE: (Podkategorija & { sekcija: string })[] = SEKCIJE.flatMap((s) =>
  s.podkategorije.map((p) => ({ ...p, sekcija: s.slug })),
);

export const sekcija = (slug: string | undefined) => SEKCIJE.find((s) => s.slug === slug);
export const podkategorija = (slug: string | undefined) => PODKATEGORIJE.find((p) => p.slug === slug);
/** Polja specifična za kategoriju (iz njezine glavne kategorije). */
export const poljaKategorije = (slug: string | undefined): Polje[] => sekcija(podkategorija(slug)?.sekcija)?.polja ?? [];

/** Boje kategorija (tamna i svijetla tema), isti redoslijed kao u aplikaciji. */
export const PALETA_TAMNA = ['#3987E5', '#D95926', '#199E70', '#C98500', '#D55181', '#008300', '#9085E9', '#E66767'];
export const PALETA_SVIJETLA = ['#2A78D6', '#EB6834', '#1BAF7A', '#EDA100', '#E87BA4', '#008300', '#6250D6', '#E34948'];

export const STANJA = ['Novo', 'Odlično', 'Vrlo dobro', 'Dobro', 'Za dijelove'] as const;
export type Stanje = (typeof STANJA)[number];

export const RAZLOZI_PRIJAVE = [
  { kljuc: 'prevara', naziv: 'Prevara' },
  { kljuc: 'krivotvorina', naziv: 'Krivotvorina' },
  { kljuc: 'neprimjereno', naziv: 'Neprimjeren sadržaj' },
  { kljuc: 'ostalo', naziv: 'Ostalo' },
] as const;
export type RazlogPrijave = (typeof RAZLOZI_PRIJAVE)[number]['kljuc'];
