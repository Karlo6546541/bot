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

- **Portfolio:** animirani prikaz kredita, status s trakom napretka do sljedeće razine,
  raspodjela vrijednosti po kategorijama.
- **Market:** čipovi kategorija s brojem uređaja, pretraga, sortiranje (najnovije, cijena, naziv)
  i **favoriti** (♥) s vlastitim filterom.
- **Detalji uređaja:** dodir na karticu otvara ekran sa specifikacijama i izračunom fee-a.
- **Kategorije:** Mobiteli, Laptopi, Tableti, Slušalice, Konzole, Satovi, Kamere, Ostalo, svaka
  sa svojom bojom i ikonom.
- **Dodaj uređaj:** birač kategorije u obliku pločica i živi pregled kartice s iznosom prodaje.
- **Aktivnost:** sažetak (zarađeno, potrošeno, plaćeni fee) i filter Kupnje/Prodaje.
- **Admin:** dashboard s brojem i vrijednošću uređaja po kategorijama.

> Ako si aplikaciju već pokretao, nove demo uređaje (Apple Watch, Sony A7 III, PS5, Switch)
> vidjet ćeš tek nakon *Profil → "Resetiraj demo podatke"*.

---

## Demo podaci za login

| Uloga    | E-mail           | Lozinka    | Napomena                                              |
|----------|------------------|------------|-------------------------------------------------------|
| Korisnik | `demo@loop.com`  | bilo koja  | 1 250 LC + iPhone 13 i Laptop Lenovo → **Silver**     |
| Korisnik | `test@loop.com`  | bilo koja  | 800 LC, prazan portfolio → **Bronze**                 |
| Admin    | `admin@loop.com` | `admin123` | preko gumba **"Admin prijava"**                       |
| Gost     | —                | —          | gumb **"Nastavi kao gost"** (500 LC)                  |

Bilo koji drugi e-mail + bilo koja lozinka automatski kreira novi račun s **500 LC** početnih kredita.

U Marketu je na početku 12 uređaja (iPhone 15 Pro, MacBook Air M3, Galaxy S24, iPad Air M2,
AirPods Pro 2, iPhone 14, MacBook Pro 14", iPad Pro 11", Apple Watch Series 9, Sony A7 III,
PlayStation 5, Nintendo Switch OLED).

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
├── models/                   # AppUser, Device, LoopTransaction, UserStatus
├── services/
│   ├── storage_service.dart  # Hive pohrana (users, devices, transactions, session)
│   ├── trade_service.dart    # poslovna logika: login, sell, buy, admin akcije
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
admin akcije, reset te UI tokove (login → prodaja → kupnja → aktivnost; kategorije, favoriti
i detalji uređaja) na desktop i mobilnoj širini.
