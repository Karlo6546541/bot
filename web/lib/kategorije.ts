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
  nazivEn: string;
  jednina: string;
  jedninaEn: string;
  ikona: number;
  emoji: string;
  boja: number;
}

export interface Sekcija {
  slug: string;
  naziv: string;
  nazivEn: string;
  ikona: number;
  boja: number;
  polja: Polje[];
  podkategorije: Podkategorija[];
}

export const SEKCIJE: Sekcija[] = [
  {
    slug: "kartice",
    naziv: "Kartice",
    nazivEn: "Cards",
    ikona: 58899,
    boja: 2,
    polja: [{ kljuc: "igra", naziv: "Igra", tip: 'izbor', opcije: ["Pokémon", "Yu-Gi-Oh!", "Digimon", "One Piece", "Magic", "Ostalo"] }, { kljuc: "set", naziv: "Set", tip: 'tekst', placeholder: "npr. Base Set" }, { kljuc: "jezik", naziv: "Jezik", tip: 'izbor', opcije: ["Engleski", "Japanski", "Njemački", "Hrvatski", "Ostalo"] }],
    podkategorije: [
    { slug: "pokemon-i-ostali-tcg", emoji: "⚡", naziv: "Pokémon i ostali TCG", nazivEn: "Pokémon and other TCG", jednina: "TCG kartica", jedninaEn: "TCG card", ikona: 57671, boja: 0 },
    { slug: "magic-the-gathering", emoji: "🧙", naziv: "Magic: The Gathering", nazivEn: "Magic: The Gathering", jednina: "MTG kartica", jedninaEn: "MTG card", ikona: 57531, boja: 1 },
    { slug: "yu-gi-oh", emoji: "🃏", naziv: "Yu-Gi-Oh!", nazivEn: "Yu-Gi-Oh!", jednina: "Yu-Gi-Oh! kartica", jedninaEn: "Yu-Gi-Oh! card", ikona: 62454, boja: 2 },
    { slug: "sportske-kartice", emoji: "🏀", naziv: "Sportske kartice", nazivEn: "Sports cards", jednina: "Kartica", jedninaEn: "Card", ikona: 58899, boja: 3 },
    { slug: "ocijenjene-kartice", emoji: "🏅", naziv: "Ocijenjene kartice", nazivEn: "Graded cards", jednina: "Ocijenjena kartica", jedninaEn: "Graded card", ikona: 62588, boja: 4 }
    ],
  },
  {
    slug: "novci",
    naziv: "Novci",
    nazivEn: "Coins and notes",
    ikona: 61917,
    boja: 3,
    polja: [{ kljuc: "drzava", naziv: "Država izdanja", tip: 'tekst', placeholder: "npr. Jugoslavija" }, { kljuc: "godina", naziv: "Godina", tip: 'broj', min: 1, max: 2100 }],
    podkategorije: [
    { slug: "kovanice", emoji: "🪙", naziv: "Kovanice", nazivEn: "Coins", jednina: "Kovanica", jedninaEn: "Coin", ikona: 61917, boja: 0 },
    { slug: "novcanice", emoji: "💶", naziv: "Novčanice", nazivEn: "Banknotes", jednina: "Novčanica", jedninaEn: "Banknote", ikona: 62054, boja: 1 },
    { slug: "zlato-i-srebro", emoji: "🥇", naziv: "Zlato i srebro", nazivEn: "Gold and silver", jednina: "Zlatnik ili srebrnjak", jedninaEn: "Gold or silver coin", ikona: 984737, boja: 2 }
    ],
  },
  {
    slug: "markice",
    naziv: "Markice",
    nazivEn: "Stamps",
    ikona: 61835,
    boja: 4,
    polja: [{ kljuc: "drzava", naziv: "Država izdanja", tip: 'tekst' }, { kljuc: "godina", naziv: "Godina", tip: 'broj', min: 1840, max: 2100 }, { kljuc: "zigosano", naziv: "Žigosano", tip: 'izbor', opcije: ["Da", "Ne"] }],
    podkategorije: [
    { slug: "markice", emoji: "✉️", naziv: "Markice", nazivEn: "Stamps", jednina: "Markica", jedninaEn: "Stamp", ikona: 61835, boja: 0 },
    { slug: "omotnice-i-filatelija", emoji: "📮", naziv: "Omotnice i filatelija", nazivEn: "Covers and philately", jednina: "Filatelistički predmet", jedninaEn: "Philatelic item", ikona: 58308, boja: 1 }
    ],
  },
  {
    slug: "razglednice-i-plakati",
    naziv: "Razglednice i plakati",
    nazivEn: "Postcards and posters",
    ikona: 62109,
    boja: 5,
    polja: [],
    podkategorije: [
    { slug: "razglednice", emoji: "🖼️", naziv: "Razglednice", nazivEn: "Postcards", jednina: "Razglednica", jedninaEn: "Postcard", ikona: 62109, boja: 0 },
    { slug: "plakati-i-reklame", emoji: "🪧", naziv: "Plakati i reklame", nazivEn: "Posters and ads", jednina: "Plakat", jedninaEn: "Poster", ikona: 61728, boja: 1 }
    ],
  },
  {
    slug: "ploce-i-mediji",
    naziv: "Ploče i mediji",
    nazivEn: "Records & media",
    ikona: 61031,
    boja: 6,
    polja: [{ kljuc: "izvodjac", naziv: "Izvođač", tip: 'tekst' }, { kljuc: "format", naziv: "Format", tip: 'izbor', opcije: ["LP", "Singlica (7\")", "Maxi (12\")", "Box set", "CD", "Kazeta"] }, { kljuc: "godina", naziv: "Godina izdanja", tip: 'broj', min: 1900, max: 2100 }],
    podkategorije: [
    { slug: "vinil", emoji: "💿", naziv: "Vinil", nazivEn: "Vinyl", jednina: "Ploča", jedninaEn: "Record", ikona: 57462, boja: 0 },
    { slug: "cd-ovi-i-kazete", emoji: "📀", naziv: "CD-ovi i kazete", nazivEn: "CDs and cassettes", jednina: "CD ili kazeta", jedninaEn: "CD or cassette", ikona: 61031, boja: 1 }
    ],
  },
  {
    slug: "stripovi",
    naziv: "Stripovi",
    nazivEn: "Comics",
    ikona: 57535,
    boja: 7,
    polja: [{ kljuc: "izdavac", naziv: "Izdavač", tip: 'tekst' }, { kljuc: "broj", naziv: "Broj izdanja", tip: 'tekst' }, { kljuc: "jezik", naziv: "Jezik", tip: 'izbor', opcije: ["Engleski", "Japanski", "Njemački", "Hrvatski", "Ostalo"] }],
    podkategorije: [
    { slug: "stripovi-i-manga", emoji: "📚", naziv: "Stripovi i manga", nazivEn: "Comics & manga", jednina: "Strip", jedninaEn: "Comic", ikona: 57535, boja: 0 },
    { slug: "jugoslavenski-stripovi", emoji: "📖", naziv: "Jugoslavenski stripovi", nazivEn: "Yugoslav comics", jednina: "Strip", jedninaEn: "Comic", ikona: 61890, boja: 1 }
    ],
  },
  {
    slug: "figure-i-igracke",
    naziv: "Figure i igračke",
    nazivEn: "Figures & toys",
    ikona: 62376,
    boja: 0,
    polja: [{ kljuc: "proizvodjac", naziv: "Proizvođač", tip: 'tekst' }, { kljuc: "kutija", naziv: "Originalna kutija", tip: 'izbor', opcije: ["Da", "Ne"] }],
    podkategorije: [
    { slug: "figure-i-funko", emoji: "🧸", naziv: "Figure i Funko", nazivEn: "Figures and Funko", jednina: "Figura", jedninaEn: "Figure", ikona: 62376, boja: 0 },
    { slug: "modeli-i-lego", emoji: "🧱", naziv: "Modeli i LEGO", nazivEn: "Models & LEGO", jednina: "Model", jedninaEn: "Model", ikona: 57936, boja: 1 }
    ],
  },
  {
    slug: "konzole-i-igre",
    naziv: "Konzole i igre",
    nazivEn: "Consoles and games",
    ikona: 58856,
    boja: 1,
    polja: [],
    podkategorije: [
    { slug: "konzole", emoji: "🎮", naziv: "Konzole", nazivEn: "Consoles", jednina: "Konzola", jedninaEn: "Console", ikona: 58856, boja: 0 },
    { slug: "videoigre", emoji: "🕹️", naziv: "Videoigre", nazivEn: "Video games", jednina: "Videoigra", jedninaEn: "Video game", ikona: 59050, boja: 1 },
    { slug: "retro-racunala", emoji: "🖥️", naziv: "Retro računala", nazivEn: "Retro computers", jednina: "Retro računalo", jedninaEn: "Retro computer", ikona: 57733, boja: 2 }
    ],
  },
  {
    slug: "memorabilije-i-autogrami",
    naziv: "Memorabilije i autogrami",
    nazivEn: "Memorabilia and autographs",
    ikona: 61466,
    boja: 2,
    polja: [],
    podkategorije: [
    { slug: "sportske-memorabilije", emoji: "🏆", naziv: "Sportske memorabilije", nazivEn: "Sports memorabilia", jednina: "Memorabilija", jedninaEn: "Memorabilia", ikona: 61466, boja: 0 },
    { slug: "autogrami", emoji: "✍️", naziv: "Autogrami", nazivEn: "Autographs", jednina: "Autogram", jedninaEn: "Autograph", ikona: 984557, boja: 1 }
    ],
  },
  {
    slug: "vojna-i-povijest",
    naziv: "Vojna i povijest",
    nazivEn: "Military and history",
    ikona: 61901,
    boja: 3,
    polja: [],
    podkategorije: [
    { slug: "vojna-i-povijesna-oprema", emoji: "🎖️", naziv: "Vojna i povijesna oprema", nazivEn: "Military and historical gear", jednina: "Povijesni predmet", jedninaEn: "Historical item", ikona: 61901, boja: 0 },
    { slug: "znacke-i-medalje", emoji: "🎖️", naziv: "Značke i medalje", nazivEn: "Badges and medals", jednina: "Značka", jedninaEn: "Badge", ikona: 61901, boja: 1 }
    ],
  },
  {
    slug: "slike-i-umjetnost",
    naziv: "Slike i umjetnost",
    nazivEn: "Art",
    ikona: 62031,
    boja: 4,
    polja: [],
    podkategorije: [
    { slug: "slike-i-crtezi", emoji: "🎨", naziv: "Slike i crteži", nazivEn: "Paintings & drawings", jednina: "Slika", jedninaEn: "Painting", ikona: 62031, boja: 0 },
    { slug: "grafike-i-fotografije", emoji: "🖼️", naziv: "Grafike i fotografije", nazivEn: "Prints and photographs", jednina: "Grafika", jedninaEn: "Print", ikona: 62110, boja: 1 }
    ],
  },
  {
    slug: "satovi",
    naziv: "Satovi",
    nazivEn: "Watches",
    ikona: 62642,
    boja: 5,
    polja: [],
    podkategorije: [
    { slug: "rucni-satovi", emoji: "🕰️", naziv: "Ručni satovi", nazivEn: "Wristwatches", jednina: "Sat", jedninaEn: "Watch", ikona: 62641, boja: 0 },
    { slug: "dzepni-i-zidni-satovi", emoji: "🕰️", naziv: "Džepni i zidni satovi", nazivEn: "Pocket and wall clocks", jednina: "Sat", jedninaEn: "Watch", ikona: 58710, boja: 1 }
    ],
  },
  {
    slug: "antikviteti-i-vintage",
    naziv: "Antikviteti i vintage",
    nazivEn: "Antiques and vintage",
    ikona: 58147,
    boja: 6,
    polja: [],
    podkategorije: [
    { slug: "vintage-i-antikviteti", emoji: "🏺", naziv: "Vintage i antikviteti", nazivEn: "Vintage & antiques", jednina: "Vintage", jedninaEn: "Vintage", ikona: 58147, boja: 0 },
    { slug: "keramika-i-porculan", emoji: "🍶", naziv: "Keramika i porculan", nazivEn: "Ceramics and porcelain", jednina: "Keramika", jedninaEn: "Ceramics", ikona: 57720, boja: 1 },
    { slug: "stari-nakit", emoji: "💍", naziv: "Stari nakit", nazivEn: "Antique jewelry", jednina: "Nakit", jedninaEn: "Jewelry", ikona: 984551, boja: 2 }
    ],
  },
  {
    slug: "elektronika",
    naziv: "Elektronika",
    nazivEn: "Electronics",
    ikona: 57803,
    boja: 7,
    polja: [],
    podkategorije: [
    { slug: "ostala-elektronika", emoji: "🔌", naziv: "Ostala elektronika", nazivEn: "Other electronics", jednina: "Elektronika", jedninaEn: "Electronics", ikona: 57804, boja: 0 },
    { slug: "mobiteli", emoji: "📱", naziv: "Mobiteli", nazivEn: "Phones", jednina: "Mobitel", jedninaEn: "Phone", ikona: 58822, boja: 1 },
    { slug: "racunala-i-laptopi", emoji: "💻", naziv: "Računala i laptopi", nazivEn: "Computers and laptops", jednina: "Računalo", jedninaEn: "Computer", ikona: 58217, boja: 2 },
    { slug: "kamere-i-foto", emoji: "📷", naziv: "Kamere i foto", nazivEn: "Cameras and photo", jednina: "Kamera", jedninaEn: "Camera", ikona: 58550, boja: 3 },
    { slug: "audio-i-slusalice", emoji: "🎧", naziv: "Audio i slušalice", nazivEn: "Audio and headphones", jednina: "Audio", jedninaEn: "Audio", ikona: 58111, boja: 4 }
    ],
  }
];

export const PODKATEGORIJE: (Podkategorija & { sekcija: string })[] = SEKCIJE.flatMap((s) =>
  s.podkategorije.map((p) => ({ ...p, sekcija: s.slug })),
);

/** Naziv na jeziku stranice ('hr' ili 'en'). */
export const nazivNa = (x: { naziv: string; nazivEn: string }, jezik: string) => (jezik === 'en' ? x.nazivEn : x.naziv);
export const jedninaNa = (x: { jednina: string; jedninaEn: string }, jezik: string) => (jezik === 'en' ? x.jedninaEn : x.jednina);

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
