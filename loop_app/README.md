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

- **Dizajn:** topla, prijateljska tržnica umjesto "burze". Svijetla tema (krem pozadina, bijele
  kartice, terakota akcent, pastelni detalji) i topla tamna tema, izbor u *Profil → Izgled*.
  Font je Nunito (ugrađen, radi offline; licenca u `assets/fonts/OFL.txt`). Iznosi se pišu
  hrvatski: „1.250 kredita”, „294,50 kredita”.
- **Kupnja kredita (demo):** paketi 50 / 100 / 250 (+10) / 500 (+30) / 1000 (+80) ili vlastiti
  iznos (10–2000), 1 kredit = 1 €. Načini plaćanja: kartica, Apple Pay, Google Pay, PayPal.
  **Ništa se stvarno ne naplaćuje i ne unose se podaci kartice.** Dnevni limit je 2000 kredita.
  Kupljeni krediti, kao i svi ostali, ne mogu se isplatiti. Dostupno s početne („Dopuni
  kredite”), iz trake s kreditima gore desno, iz Profila te automatski kad za kupnju ili
  ponudu nema dovoljno kredita.
- **Početna:** brze akcije (Kupi kredite, Dodaj predmet, Market, Aukcije) i kartica „Kako LOOP
  radi” koja se može zatvoriti.
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

  **Protiv masovnog stavljanja svega na aukcije** (`lib/services/auction_policy.dart`):
  - limit aktivnih aukcija po statusu: Bronze 2, Silver 4, Gold 6;
  - najviše 3 nove aukcije u 24 sata;
  - na aukciju idu samo predmeti vrijedni barem 50 kredita (sitnice → Market);
  - naknada za objavu: 2% vrijednosti predmeta (najmanje 2 kredita), ne vraća se;
  - predmet koji se nije prodao može ponovno na aukciju tek nakon 24 h;
  - pri objavi se prikazuje usporedba „Prodaj odmah” (sigurno, bez naknade) i aukcije,
    uz gumb „Radije prodaj odmah”.

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

## Jezik: hrvatski / English

- Gumb **🇭🇷 HR / 🇬🇧 EN** u gornjoj traci (i na ekranu prijave i u admin panelu) prebacuje
  jezik jednim dodirom; na mobitelu se prikazuje samo zastavica.
- U **Profilu** je postavka *Jezik / Language* (🇭🇷 Hrvatski / 🇬🇧 English).
- Odabir se pamti na uređaju (kao i tema) i ostaje nakon resetiranja demo podataka.
- Na engleskom se mijenja i zapis brojeva i datuma: `1,250 credits`, `€49.99`, `Oct 21, 2026 14:30`.
- Prijevodi su u `lib/l10n/en.dart`; ključ je hrvatski tekst iz koda, npr.
  `t('Prodaj odmah')` → *Sell now*, a `{0}` je mjesto za vrijednost:
  `t('Bok, {0} 👋', [ime])`. Nazivi predmeta, opisi i povijest transakcija ostaju kako su upisani.

Svaki predmet ima i **opis** (neobavezno, do 500 znakova) koji se upisuje pri dodavanju i
prikazuje na detaljima predmeta i aukcije.

---

## Dostava kupljenih predmeta (demo)

- **Market:** pri kupnji se otvara blagajna s odabirom dostave i ukupnim iznosom
  (predmet + 5% fee + dostava).
- **Aukcije:** pobjednik dobiva pošiljku koja čeka odabir dostave (*Profil → Moje dostave*
  ili traka na početnoj).

| Način | Cijena | Demo trajanje | Napomena |
|---|---|---|---|
| Osobno preuzimanje | besplatno | 2 min | LOOP točka |
| Paketomat | 3 kredita | 3 min | odabir paketomata |
| Kurir na adresu | 6 kredita | 4 min | adresa se pamti |
| Ekspresna dostava | 12 kredita | 2 min | |
| Digitalna dostava | besplatno | 1 min | samo za Aktivnosti (ulaznice, radionice…) |

Statusi (Naručeno → Zapakirano → Poslano → U dostavi → Dostavljeno) računaju se iz vremena,
pa su isti na svim uređajima. Trajanje je ubrzano s dana na minute kako bi se moglo pratiti
uživo. Svaka pošiljka ima broj za praćenje (`LOOP-XXXXXXXX`), a kupac nakon isporuke
potvrđuje primitak.

### Ideje za pravu dostavu (sljedeći koraci)

- **Escrow:** krediti kupca se drže dok ne potvrdi primitak (ili 3 dana nakon isporuke), a tek
  onda idu prodavatelju. To štiti od neisporuke i vrijedi posebno za aukcije među korisnicima.
- **Prava dostavna služba:** API dostavljača (npr. paketomati i kurirske službe u RH) za
  naljepnice, praćenje u stvarnom vremenu (webhook → status pošiljke) i odabir paketomata na karti.
- **Slanje prodanog predmeta LOOP-u:** besplatna naljepnica za "Prodaj odmah"; krediti stižu
  nakon provjere stanja predmeta na LOOP točki (sprječava prodaju neispravnih uređaja).
- **Provjera stanja + reklamacija:** 48 h nakon primitka za prijavu problema s fotografijama;
  povrat kredita ako se predmet ne slaže s opisom.
- **Osiguranje pošiljke** za skuplje predmete (npr. iznad 500 kredita) kao dodatna opcija.
- **Osobna primopredaja** među korisnicima u istom gradu, uz QR kod koji potvrđuje primopredaju.
- **Ocjene** prodavatelja i dostave nakon potvrde primitka.

---

## Online testiranje (Supabase + web link)

Aplikacija radi **lokalno prvo**: čita i piše na uređaju, a kad je postavljena online baza,
sve promjene šalje u **Supabase** i u stvarnom vremenu prima promjene drugih testera.
Bez postavki radi offline, kao prije.

### 1. Supabase (besplatno)

1. Otvori račun na https://supabase.com i **New project** (regija npr. *Frankfurt*).
2. **SQL Editor → New query** → zalijepi cijeli `supabase/schema.sql` → **Run**.
3. **Project Settings → API**: kopiraj **Project URL** i **Publishable key**
   (`sb_publishable_…`; u starijim projektima *anon public* ključ).

> ⚠️ Testna shema dopušta svakome s javnim ključem čitanje i pisanje svih podataka.
> Koristi je samo za testiranje s izmišljenim podacima.

### 2. Pokretanje aplikacije spojene na bazu

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://TVOJ-PROJEKT.supabase.co `
  --dart-define=SUPABASE_KEY=sb_publishable_TVOJ_KLJUC
```

Prvi klijent koji se spoji na praznu bazu pošalje u nju demo podatke, a svi sljedeći ih
preuzmu. *Profil* prikazuje stanje veze (🟢 povezano / 🟠 nedostupno / ⚪ lokalno).
*Resetiraj demo podatke* resetira i online bazu.

### 3. Web link za testere (GitHub Pages, besplatno)

Workflow `.github/workflows/loop-web.yml` pri svakom pushu pokreće testove, gradi web verziju
i objavljuje je na **https://karlo6546541.github.io/bot/**.

1. GitHub → repozitorij → **Settings → Pages → Build and deployment → Source:
   GitHub Actions**.
2. **Settings → Secrets and variables → Actions → New repository secret**:
   `SUPABASE_URL` i `SUPABASE_KEY` (iste vrijednosti kao gore).
3. **Actions → LOOP web (GitHub Pages) → Run workflow**.
4. Ako deploy javi da grana nije dopuštena: **Settings → Environments → github-pages →
   Deployment branches** i dodaj `claude/beautiful-newton-sftcyd` (ili spoji granu u `main`).

**Fotografije:** s online bazom spremaju se u Supabase Storage (bucket `loop-images`,
`supabase/storage.sql`) i vide ih svi testeri, na webu i u aplikaciji. Bez baze se na webu
spremaju u preglednik (smanjene), a na Windowsu i mobitelu u mapu aplikacije.

### Put do produkcije

Testna verzija sinkronizira dokumente i pravila provjerava u aplikaciji. Za pravo
korištenje treba:
- **Supabase Auth** (pravi računi) i RLS pravila po korisniku: svatko piše samo svoje podatke;
- **kupnje, ponude, dopune i zaključivanje aukcija kao funkcije na serveru** (Postgres
  funkcije ili Edge Functions), koje u jednoj transakciji provjeravaju kredite i pravila,
  da ih klijent ne može zaobići i da dvije istovremene kupnje istog predmeta ne prođu;
- pravila za Storage po korisniku (svatko briše samo svoje slike) i provjeru veličine/vrste
  na serveru;
- zaključivanje aukcija i statuse dostava putem zakazanog posla (cron) na serveru.

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
│   ├── credit_shop.dart      # kupnja kredita: paketi, bonus, dnevni limit (demo)
│   ├── delivery_service.dart # dostava: načini, naplata, praćenje, potvrda primitka
│   ├── auction_policy.dart   # limiti i naknada za objavu aukcija
│   ├── remote_store.dart     # Supabase (online baza) + sučelje za testove
│   ├── sync_service.dart     # sinkronizacija lokalno ⇄ online u stvarnom vremenu
│   ├── image_store.dart      # odabir i lokalno spremanje fotografija
│   ├── fee.dart              # 5% fee i izračuni
│   └── seed_data.dart        # demo podaci
├── providers/
│   ├── app_state.dart        # nepromjenjiva snimka stanja + izvedene vrijednosti
│   └── app_providers.dart    # Riverpod Notifier s akcijama
├── screens/                  # login, portfolio, market, dodaj uređaj, aktivnost, profil
├── admin/                    # admin panel: dashboard, korisnici, uređaji, transakcije
├── widgets/                  # kartice, dijalozi, responzivni okvir, formatiranje
├── config/                   # postavke online baze (--dart-define)
├── l10n/                     # t('...') + engleski prijevodi (kEn)
├── utils/                    # formatiranje iznosa i datuma (hrvatski zapis)
└── theme/                    # svijetla i tamna Material 3 tema, paleta boja
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
povijest vrijednosti, fotografije, odjeljke, **kupnju kredita** (bonus, dnevni limit),
hrvatski i engleski format iznosa, promjenu teme i **jezika** (svaki tekst ima prijevod), **pravila aukcija** (blokiranje i povrat
kredita, obvezujuće ponude, limit kredita, produljenje, zaključivanje, nadogradnja), admin akcije
i reset te UI tokove (login → prodaja →
kupnja → aktivnost; kategorije, favoriti, detalji; grafikon i odjeljci) na desktop i mobilnoj širini.
