# LOOP — Trade. Don't sell.

Demo Flutter aplikacija: zatvorena trading platforma za rabljene uređaje
(mobiteli, laptopi, tableti, slušalice, konzole).

- Prodajom uređaja ne dobivaš novac, nego **LOOP kredite** (LC).
- Krediti se troše **isključivo** na kupnju drugih uređaja unutar aplikacije — nema isplate.
- Platforma uzima **5% fee** na svaku transakciju.
- Sve radi **lokalno i offline** (Hive), bez backenda.

Platforme: **Windows, Android, iOS**.

---

## Brzi start

Potrebno: [Flutter SDK](https://docs.flutter.dev/get-started/install), aktualni **stable** kanal
(Dart ≥ 3.12). Ako imaš stariju verziju: `flutter upgrade`.

```bash
cd loop_app
flutter pub get
flutter run            # odaberi uređaj s popisa
```

### Windows

1. Instaliraj **Visual Studio 2022** s workloadom *"Desktop development with C++"*.
2. Provjeri: `flutter doctor` (stavka *Visual Studio* mora biti ✓).
3. Pokreni:
   ```bash
   flutter run -d windows
   ```
4. Release build: `flutter build windows` → `build\windows\x64\runner\Release\loop_app.exe`

### Android

1. Instaliraj **Android Studio** (Android SDK + emulator) i prihvati licence:
   `flutter doctor --android-licenses`.
2. Pokreni emulator ili spoji mobitel s uključenim *USB debuggingom*.
3. Pokreni:
   ```bash
   flutter devices              # provjeri da je uređaj vidljiv
   flutter run -d <id-uređaja>
   ```
4. APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`

### iOS (samo na macOS-u)

1. Instaliraj **Xcode** i **CocoaPods** (`brew install cocoapods`).
2. Pokreni simulator (`open -a Simulator`) i:
   ```bash
   flutter run -d ios
   ```
   (Flutter sam pokreće `pod install` pri prvom buildu.)
3. Za pravi iPhone: otvori `ios/Runner.xcworkspace` u Xcodeu, pod *Signing & Capabilities*
   odaberi svoj Team, pa `flutter run`.

### Što aplikacija ima

- **Aukcije:** objavi predmet iz svog portfolija (početna cijena i trajanje od 2 min do 7 dana),
  ostali licitiraju. Pravila:
  - ponuda je **obvezujuća** i ne može se povući ni smanjiti;
  - vodeći ponuđač ne može dati novu ponudu dok ga netko ne nadmaši;
  - ponuda ne može biti **veća od raspoloživih kredita**;
  - iznos vodeće ponude se **blokira** na računu i vraća se čim te netko nadmaši;
  - najmanji korak je 5% trenutne cijene;
  - ponuda u zadnjoj minuti produljuje aukciju za 1 minutu;
  - na kraju pobjednik dobiva predmet, a prodavatelj najvišu ponudu − 5% feeja;
  - bez ponuda predmet ostaje prodavatelju, koji aukciju može otkazati samo dok nema ponuda.

  Dok aukcija traje, predmet se ne može prodati. Aukcije se zaključuju dok je aplikacija
  otvorena: nema servera, pa ih aplikacija provjerava svake 3 sekunde i pri pokretanju.
- **Pet odjeljaka Marketa:** Elektronika, Kolekcionarstvo (kartice, kovanice, marke, figure,
  ploče), Hobiji (sport, instrumenti, knjige, društvene igre, LEGO), Rukotvorine (nakit,
  keramika, tekstil, drvo, slike) i Aktivnosti (radionice, poduke, ulaznice, doživljaji).
- **Fotografije predmeta:** do 4 po predmetu. Na Windowsu se biraju datoteke, a na mobitelu
  galerija ili kamera. Dodaju se pri unosu ili kasnije na ekranu detalja. Predmeti bez
  fotografije prikazuju ilustraciju kategorije.
- **Grafikon portfolija:** vrijednost (krediti + predmeti) kroz vrijeme s rasponima 7D/30D/Sve,
  crosshair i tooltip na prelazak mišem ili dodir, te tablični prikaz istih podataka.
- **Portfolio:** animirani krediti, traka napretka do sljedećeg statusa i raspodjela po
  odjeljcima/kategorijama.
- **Market:** odjeljci, kategorije, pretraga, sortiranje i **favoriti** (♥).
- **Detalji predmeta:** galerija, specifikacije, izračun feeja i kupnja/prodaja.
- **Aktivnost:** sažetak (zarađeno, potrošeno, plaćeni fee) i filter Kupnje/Prodaje.
- **Admin:** dashboard s predmetima po odjeljcima.

> Ažuriranje sa starije verzije: novi demo predmeti i početna točka grafikona dodaju se
> automatski pri prvom pokretanju, bez resetiranja.

**Boje u grafikonima** dolaze iz validirane kategorijske palete (`kCategoricalPalette` u
`lib/widgets/category_style.dart`). Provjerene su na tamnoj pozadini aplikacije: raspon
svjetline, kontrast i razlučivost za daltonizam.

---

## Demo podaci za login

| Uloga    | E-mail           | Lozinka    | Napomena                                              |
|----------|------------------|------------|-------------------------------------------------------|
| Korisnik | `demo@loop.com`  | bilo koja  | 1 250 LC + iPhone 13 i Laptop Lenovo → **Silver**     |
| Korisnik | `test@loop.com`  | bilo koja  | 800 LC, prazan portfolio → **Bronze**                 |
| Admin    | `admin@loop.com` | `admin123` | preko gumba **"Admin prijava"**                       |
| Gost     | —                | —          | gumb **"Nastavi kao gost"** (500 LC)                  |
| Korisnik | `ana@loop.com`   | bilo koja  | prodaje 4 predmeta na aukcijama                       |
| Korisnik | `marko@loop.com` | bilo koja  | vodi na 3 aukcije (470 LC blokirano)                  |

Bilo koji drugi e-mail + bilo koja lozinka automatski kreira novi račun s **500 LC** početnih kredita.

U Marketu je na početku 31 predmet: 12 iz elektronike (iPhone 15 Pro, MacBook Air M3,
Galaxy S24, iPad Air M2, AirPods Pro 2, iPhone 14, MacBook Pro 14", iPad Pro 11",
Apple Watch, Sony A7 III, PS5, Switch) i po 4–5 iz svakog novog odjeljka.

**Resetiranje:** *Profil → "Resetiraj demo podatke"* briše sve i vraća početno stanje.

---

## Poslovna pravila

| Akcija           | Formula                   | Primjer (cijena 310 LC)   |
|------------------|---------------------------|---------------------------|
| **Prodaj odmah** | dobivaš `cijena × 0.95`   | +294.50 LC (fee 15.50)    |
| **Kupi odmah**   | plaćaš `cijena × 1.05`    | −325.50 LC (fee 15.50)    |

- Prodani uređaj ide u **Market** (otkupljuje ga platforma) gdje ga drugi mogu kupiti.
- Kupnja je moguća samo ako imaš dovoljno kredita za cijenu **+ fee**.
- Prije svake transakcije prikazuje se dijalog s cijenom, fee-om i konačnim iznosom.
- **Status** = krediti + vrijednost portfolija: Bronze < 2000 · Silver 2000–5000 · Gold > 5000.

Fee je definiran na jednom mjestu: `lib/services/fee.dart` (`kFeeRate`).

---

## Struktura koda

```
lib/
├── main.dart                 # bootstrap: init Hive + splash, ProviderScope
├── app.dart                  # MaterialApp; login / korisnik / admin prema sesiji
├── models/                   # AppUser, Device (+ odjeljci/kategorije), Auction, LoopTransaction,
│                             # PortfolioPoint, UserStatus
├── services/
│   ├── storage_service.dart  # Hive pohrana (users, devices, transactions, session)
│   ├── trade_service.dart    # poslovna logika: login, sell, buy, povijest, admin akcije
│   ├── auction_service.dart  # aukcije: objava, ponude, blokiranje kredita, zaključivanje
│   ├── image_store.dart      # odabir i lokalno spremanje fotografija
│   ├── fee.dart              # 5% fee i izračuni
│   └── seed_data.dart        # demo podaci
├── providers/
│   ├── app_state.dart        # nepromjenjiva snimka stanja + izvedene vrijednosti
│   └── app_providers.dart    # Riverpod Notifier s akcijama
├── screens/                  # login, portfolio, market, dodaj uređaj, aktivnost, profil
├── admin/                    # admin panel: dashboard, korisnici, uređaji, transakcije
├── widgets/                  # kartice, dijalozi, responzivni okvir, formatiranje
└── theme/                    # tamna Material 3 tema i boje
```

- **State management:** Riverpod (`Notifier`). Nakon svake akcije stanje se ponovno učita iz
  pohrane pa se UI osvježava odmah.
- **Pohrana:** Hive boxovi s običnim mapama — nisu potrebni generirani adapteri ni `build_runner`.
- **Responzivnost:** ispod 840 px širine Bottom Navigation Bar, iznad Navigation Rail (sidebar).
- **Admin panel** koristi narančasti akcent i zaseban AppBar.

## Testovi

```bash
flutter analyze
flutter test
```

Testovi pokrivaju fee, status, prodaju, kupnju (uključujući nedovoljno kredita), favorite,
povijest vrijednosti, fotografije, odjeljke, **pravila aukcija** (blokiranje i povrat
kredita, obvezujuće ponude, limit kredita, produljenje, zaključivanje, nadogradnja), admin akcije
i reset te UI tokove (login → prodaja →
kupnja → aktivnost; kategorije, favoriti, detalji; grafikon i odjeljci) na desktop i mobilnoj širini.
