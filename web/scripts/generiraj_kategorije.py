#!/usr/bin/env python3
"""Generira web/lib/kategorije.ts iz Flutter koda (jedini izvor istine za kategorije).

Čita: loop_app/lib/models/device.dart (ItemSection, DeviceCategory),
loop_app/lib/widgets/category_style.dart (ikone) i Flutter icons.dart (kodovi ikona).
Pokretanje: python3 web/scripts/generiraj_kategorije.py <putanja do flutter/packages/flutter/lib/src/material/icons.dart>
"""
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
device = (ROOT / 'loop_app/lib/models/device.dart').read_text()
stil = (ROOT / 'loop_app/lib/widgets/category_style.dart').read_text()
icons_src = Path(sys.argv[1]).read_text()
en_src = (ROOT / 'loop_app/lib/l10n/en.dart').read_text()
EN = {}
for m in re.finditer(r"^\s*'((?:[^'\\]|\\.)*)':\s*'((?:[^'\\]|\\.)*)',", en_src, re.M):
    EN.setdefault(m.group(1).replace("\\'", "'"), m.group(2).replace("\\'", "'"))
def en(t):
    if t not in EN:
        raise SystemExit(f'nema engleskog prijevoda za {t!r} u en.dart')
    return EN[t]

# ---- ikone: ime -> kod ----
kodovi = {}
for m in re.finditer(r'static const IconData (\w+) =\s*IconData\(\s*(0x[0-9a-fA-F]+)', icons_src):
    kodovi.setdefault(m.group(1), int(m.group(2), 16))

# ---- ItemSection ----
a = device.index('enum ItemSection {')
b = device.index(';', device.index("const ItemSection(this._label);") - 400)
blok = device[a:device.index('const ItemSection(this._label)')]
sekcije_sve = re.findall(r"^\s*(\w+)\('([^']*)'\)", blok, re.M)
act_s = re.search(r'static const active = <ItemSection>\[(.*?)\];', device, re.S).group(1)
sekcije_aktivne = re.findall(r'\w+', act_s)

# ---- DeviceCategory ----
a = device.index('enum DeviceCategory {')
blok = device[a:device.index('const DeviceCategory(this._label')]
kat = re.findall(r"(\w+)\(\s*'([^']*)',\s*'([^']*)',\s*ItemSection\.(\w+),?\s*\)", blok)
act_k = re.search(r'static const active = <DeviceCategory>\[(.*?)\];', device, re.S).group(1)
kat_aktivne = re.findall(r'\w+', act_k)

ikona_kat = dict(re.findall(r'DeviceCategory\.(\w+) => Icons\.(\w+),', stil))
ikona_sek = dict(re.findall(r'ItemSection\.(\w+) => Icons\.(\w+),', stil))


def slug(s: str) -> str:
    s = s.lower().replace('đ', 'd')
    s = unicodedata.normalize('NFD', s)
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]+', '-', s).strip('-')


def kod(ime: str) -> int:
    if ime not in kodovi:
        raise SystemExit(f'nema koda za ikonu {ime}')
    return kodovi[ime]


POLJA = {
    'cardsMain': [('igra', 'Igra', 'izbor', ['Pokémon', 'Yu-Gi-Oh!', 'Digimon', 'One Piece', 'Magic', 'Ostalo']), ('set', 'Set', 'tekst', 'npr. Base Set'), ('jezik', 'Jezik', 'izbor', ['Engleski', 'Japanski', 'Njemački', 'Hrvatski', 'Ostalo'])],
    'coinsMain': [('drzava', 'Država izdanja', 'tekst', 'npr. Jugoslavija'), ('godina', 'Godina', 'broj', (1, 2100))],
    'stampsMain': [('drzava', 'Država izdanja', 'tekst', None), ('godina', 'Godina', 'broj', (1840, 2100)), ('zigosano', 'Žigosano', 'izbor', ['Da', 'Ne'])],
    'comicsMain': [('izdavac', 'Izdavač', 'tekst', None), ('broj', 'Broj izdanja', 'tekst', None), ('jezik', 'Jezik', 'izbor', ['Engleski', 'Japanski', 'Njemački', 'Hrvatski', 'Ostalo'])],
    'figuresMain': [('proizvodjac', 'Proizvođač', 'tekst', None), ('kutija', 'Originalna kutija', 'izbor', ['Da', 'Ne'])],
    'mediaMain': [('izvodjac', 'Izvođač', 'tekst', None), ('format', 'Format', 'izbor', ['LP', 'Singlica (7")', 'Maxi (12")', 'Box set', 'CD', 'Kazeta']), ('godina', 'Godina izdanja', 'broj', (1900, 2100))],
}


def ts(v):
    import json
    return json.dumps(v, ensure_ascii=False)


def polje(p):
    kljuc, naziv, tip, extra = p
    if tip == 'izbor':
        return f"{{ kljuc: {ts(kljuc)}, naziv: {ts(naziv)}, tip: 'izbor', opcije: {ts(extra)} }}"
    if tip == 'broj':
        return f"{{ kljuc: {ts(kljuc)}, naziv: {ts(naziv)}, tip: 'broj', min: {extra[0]}, max: {extra[1]} }}"
    pl = f", placeholder: {ts(extra)}" if extra else ''
    return f"{{ kljuc: {ts(kljuc)}, naziv: {ts(naziv)}, tip: 'tekst'{pl} }}"


kat_po = {n: (l, j, s) for n, l, j, s in kat}
izlaz = []
for idx_all, (ime_s, lab_s) in enumerate(sekcije_sve):
    if ime_s not in sekcije_aktivne:
        continue
    podk = [k for k in kat_aktivne if kat_po[k][2] == ime_s]
    stavke = []
    for i, k in enumerate(podk):
        lab, jed, _ = kat_po[k]
        stavke.append(
            f"    {{ slug: {ts(slug(lab))}, naziv: {ts(lab)}, nazivEn: {ts(en(lab))}, jednina: {ts(jed)}, jedninaEn: {ts(en(jed))}, ikona: {kod(ikona_kat[k])}, boja: {i % 8}, emoji: '' }}"
        )
    polja = ', '.join(polje(p) for p in POLJA.get(ime_s, []))
    izlaz.append(
        f"  {{\n    slug: {ts(slug(lab_s))},\n    naziv: {ts(lab_s)},\n    nazivEn: {ts(en(lab_s))},\n    ikona: {kod(ikona_sek[ime_s])},\n    boja: {idx_all % 8},\n    polja: [{polja}],\n    podkategorije: [\n" + ',\n'.join(stavke) + '\n    ],\n  }'
    )

# emoji po kategoriji
emoji = dict(re.findall(r"DeviceCategory\.(\w+) => '([^']*)',", stil[stil.index('extension CategoryEmoji'):]))
sadrzaj = ',\n'.join(izlaz)
for k in kat_aktivne:
    lab = kat_po[k][0]
    sadrzaj = sadrzaj.replace(f'{{ slug: {ts(slug(lab))}, naziv: {ts(lab)},', f'{{ slug: {ts(slug(lab))}, emoji: {ts(emoji.get(k, ""))}, naziv: {ts(lab)},', 1)
sadrzaj = sadrzaj.replace(", emoji: '' }", ' }')

zaglavlje = """// GENERIRANO skriptom web/scripts/generiraj_kategorije.py iz Flutter koda
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
"""
dno = """
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
"""
(ROOT / 'web/lib/kategorije.ts').write_text(zaglavlje + sadrzaj + dno)
print(f'{len(izlaz)} glavnih kategorija, {sum(len(kat_aktivne) for _ in [0])} podkategorija')
