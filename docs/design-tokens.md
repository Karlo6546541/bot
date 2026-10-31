# Subhasto: dizajnerski tokeni

Izvor istine: `loop_app/lib/theme/app_theme.dart` (`LoopColors`, `kRadius`,
`kFontFamily`, `buildLoopTheme`) i `loop_app/lib/widgets/adaptive_shell.dart`.
Redizajn se drži samo ovih vrijednosti: nove boje, fontovi i oblici se ne
uvode. Ako element nema pandana, izvodi se iz ovih tokena (npr. tamniji ili
prozirniji ton postojeće boje).

Zadana tema je **svijetla**; tamna je dostupna u postavkama. Live soba je
uvijek tamna (`buildLiveTheme`).

## Boje (`LoopColors`)

| Uloga | Svijetla | Tamna | Gdje |
|---|---|---|---|
| `background` | `#FFF7EF` (krem) | `#17120F` | pozadina ekrana |
| `surface` | `#FFFFFF` | `#221B17` | kartice, sheetovi, polja |
| `surfaceHover` | `#FFEFE2` | `#2E2520` | rubovi polja, razdjelnici, odabrane površine |
| `accent` | `#C2410C` (terakota) | `#FF9248` | glavne radnje: Licitiraj, Kupi, Objavi; odabrano |
| `onAccent` | `#FFFFFF` | `#1B1410` | tekst/ikone na akcentu |
| `live` | `#FF2D55` | isto | isključivo "UŽIVO" |
| `buyNow` | `#15803D` | `#4CC38A` | Kupi odmah, dostavljeno, zaštita kupca |
| `textPrimary` | `#2A1F17` | `#F5EDE6` | naslovi, tijelo |
| `textSecondary` | `#76685D` | `#B3A69B` | opisi, neaktivno |
| `error` | `#C92A3A` | `#FF7B7B` | |
| `success` | `#1A7F4E` | `#4CC38A` | |
| `info` | `#1E6FD9` | `#6CB4FF` | "Provjeren", informativne oznake |
| `admin` | `#4F46E5` | `#A8A2FF` | samo admin panel |

Pastelne pločice (samo dekoracija, nikad tekst): `peach` `#FFE1D1`,
`sunny` `#FFEDB8`, `mint` `#D6F2E3`, `lilac` `#E7E0FF`, `sky` `#D9ECFF`,
`rose` `#FFD9E0` (tamne varijante u `app_theme.dart`).

Pravila: narančasto/terakota je **jedina** boja radnji; crvena samo za live;
zelena za kupnju i zaštitu. Boje se ne miješaju. Kontrast teksta ≥ 4,5:1.

Mobilna donja traka: pozadina `#26272C`, aktivno `#E9E9ED`, neaktivno `#92939D`.

## Tipografija

- Font: **Nunito** (ugrađen, offline). Težine 400, 600, 700, 800, 900.
- Posebni fontovi samo za priče/naslovnice: BebasNeue, SpaceMono Bold, Pacifico.
- Veličine koje aplikacija koristi: 11, 12, 13 (sitni tekst, oznake, metapodaci),
  14–16 (tijelo, gumbi), 18–22 (naslovi, cijene), 24+ (hero).
- AppBar naslov 22 / 800. Gumb 16 / 800 (filled), 15 / 700 (outlined).
  Tab/čip 600. Oznake (pill) 11 / 900.

## Oblici, razmaci, sjene

- Radijus: `kRadius = 18` (kartice, dijalozi, polja, snackbar); pilule
  (`StadiumBorder`) za gumbe, čipove, FAB; 8 za male oznake i donju ikonu `+`.
- Gumbi: minimalno 64 × 52, `StadiumBorder`. Outlined: rub `surfaceHover` 2 px.
- Polja: ispuna `surface`, rub `surfaceHover` 1,5 px, fokus `accent` 2 px,
  padding 18 × 16.
- Čip: pilula, rub `surfaceHover`, odabran = `accent` 16 % prozirnosti.
- Navigacija: indikator `accent` 16 %; aktivna ikona `accent`.
- Sjena kartice (`softShadow`): svijetla `#8A5A3C` 10 %, blur 18, y 6;
  tamna crna 25 %. `Card`: elevation 1,5 (svijetla) / 0 (tamna), margin 0.
- Razmaci: 4 / 6 / 8 / 10 / 12 / 16 / 24 (višekratnici 2 i 4).
- Mreža kartica: 4:5 slika (`BrowseGridDelegate`, max širina pločice 240,
  razmak 12, red 18).
- Breakpoint: `kDesktopBreakpoint = 840` (ispod: donja traka, iznad: rail).
- Dodirne površine ≥ 44 px (iz zahtjeva redizajna).

## Ikone

Material ikone (Material Icons, obrisne varijante gdje postoje), 20–25 px.
Logo: koplje (spear) iz rebrandinga; emoji samo u oznakama (📅, 🏷️, 🔥).

## Komponente (postojeće, koristiti ih)

`LiveBadge`, `AuctionBrowseCard` (`lib/screens/auctions_screen.dart`),
`AdaptiveShell`/`ShellDestination`, `UserAvatar`, `CountryBadge`, `PriceTag`,
`ItemThumb`, `RoleBadge`, `AuctionCountdown`, `appThemed`.
