/** Fake demo content used by scripts/seed.ts and scripts/generate-seed-assets.ts */
export const SEED_PASSWORD = "lozinka123";

export const seedUsers = [
  { email: "admin@kadar.test", displayName: "Admin", role: "admin" as const },
  { email: "ana@kadar.test", displayName: "Ana Kovač", role: "creator" as const, penName: "Ana Kovač" },
  { email: "marko@kadar.test", displayName: "Marko Babić", role: "creator" as const, penName: "Marko Babić" },
  { email: "citatelj@kadar.test", displayName: "Iva Čitateljica", role: "reader" as const },
  { email: "pretplatnik@kadar.test", displayName: "Luka Pretplatnik", role: "reader" as const },
];

export interface SeedSeries {
  slug: string;
  title: string;
  creatorEmail: string;
  description: string;
  genres: string[];
  freeChapters: number;
  palette: [string, string, string];
  chapters: { title: string; access?: "free" | "locked" | "early_access"; earlyDays?: number; publishInDays?: number }[];
}

export const seedSeries: SeedSeries[] = [
  {
    slug: "sjene-nad-gornjim-gradom",
    title: "Sjene nad Gornjim gradom",
    creatorEmail: "ana@kadar.test",
    description:
      "Kad se na Kamenitim vratima ugasi plamen koji gori stoljećima, mlada arhivistica Petra otkriva da zagrebačke legende nisu samo priče.",
    genres: ["mystery", "fantasy"],
    freeChapters: 3,
    palette: ["#1d2b53", "#7e2553", "#ffccaa"],
    chapters: [
      { title: "Ugašeni plamen" },
      { title: "Arhiv pod Lotrščakom" },
      { title: "Grička vještica" },
      { title: "Tunel ispod Tkalčićeve" },
      { title: "Tko pali svjetla" },
      { title: "Ponoćni top", access: "early_access", earlyDays: 7 },
    ],
  },
  {
    slug: "galeb-i-more",
    title: "Galeb i more",
    creatorEmail: "marko@kadar.test",
    description:
      "Ljeto na malom dalmatinskom otoku, jedan tvrdoglavi galeb i trajekt koji nikad ne kasni — osim kad je najvažnije.",
    genres: ["slice_of_life", "comedy"],
    freeChapters: 2,
    palette: ["#0b6e99", "#f4d35e", "#faf0ca"],
    chapters: [
      { title: "Prvi trajekt" },
      { title: "Fjaka" },
      { title: "Riba nije za galebe" },
      { title: "Fešta" },
      { title: "Bura", access: "early_access", earlyDays: 14 },
    ],
  },
  {
    slug: "orbita-velebit",
    title: "Orbita Velebit",
    creatorEmail: "ana@kadar.test",
    description:
      "Godina 2147. Posljednja hrvatska svemirska postaja nosi ime planine koju posada nikad nije vidjela.",
    genres: ["scifi", "adventure"],
    freeChapters: 1,
    palette: ["#0d0221", "#2de2e6", "#ff6c11"],
    chapters: [
      { title: "Buđenje" },
      { title: "Signal s Marsa" },
      { title: "Šetnja u vakuumu" },
      { title: "Velebitska legenda", access: "free" },
      { title: "Povratak", publishInDays: 5 },
    ],
  },
];

export const PAGES_PER_CHAPTER = 4;
