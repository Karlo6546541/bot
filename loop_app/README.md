# LOOP — Trade. Don't sell.

Demo Flutter aplikacija: zatvorena trading platforma za rabljene uređaje
(mobiteli, laptopi, tableti, slušalice, konzole).

- Prodajom uređaja ne dobivaš novac, nego **LOOP kredite** (LC).
- Krediti se troše **isključivo** na kupnju drugih uređaja unutar aplikacije — nema isplate.
- Platforma uzima **5% fee** na svaku transakciju.
- Radi **lokalno i offline** (Hive), a uz Supabase i **online** s pravim računima.

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
- **Market:** traka s pretragom i gumbom **Filteri** ostaje na vrhu pri skrolanju; brzi
  odabir odjeljka/kategorije, a u listu filtera stanje, raspon cijene, prodavatelj (LOOP /
  korisnici), samo favoriti i samo s fotografijom uz broj rezultata uživo. Aktivni filteri
  su čipovi koji se brišu jednim dodirom (*Očisti sve*); sortiranje pokazuje trenutni izbor.
  Filteri ostaju i nakon promjene taba, teme ili jezika.
- **Detalji predmeta:** galerija, specifikacije, izračun feeja i kupnja/prodaja.
- **Aktivnost:** sažetak (zarađeno, potrošeno, plaćeni fee) i filter Kupnje/Prodaje.
- **Admin:** dashboard s predmetima po odjeljcima.

> Ažuriranje sa starije verzije: novi demo predmeti i početna točka grafikona dodaju se
> automatski pri prvom pokretanju, bez resetiranja.

**Boje u grafikonima** dolaze iz validirane kategorijske palete (`kCategoricalPalette` u
`lib/widgets/category_style.dart`). Provjerene su na tamnoj pozadini aplikacije: raspon
svjetline, kontrast i razlučivost za daltonizam.

---

## Računi i profil

- **Registracija** e-mailom, lozinkom (barem 6 znakova) i **korisničkim imenom**; prijava
  e-mailom (lokalno i korisničkim imenom). Novi računi dobivaju 500 LC.
- **Jedinstveno korisničko ime** (`@ime`): 3–20 znakova (a–z, brojevi, `_`, `.`), počinje
  slovom, bez rezerviranih (`admin`, `loop`, `support`…) i neprimjerenih imena; "Karlo" i
  "karlo" su isto ime. Dok tipkaš vidiš je li slobodno, a ako nije, dobiješ prijedloge.
  Mijenja se najviše jednom u 30 dana, a staro ime ostaje zaključano 30 dana.
  Online jedinstvenost jamči i baza (tablica `loop_usernames`, ime je primarni ključ).
- **Google prijava** (web link s online bazom): pri prvoj prijavi biraš korisničko ime.
- **Zaboravljena lozinka**: online stiže link na e-mail; lokalno se nova lozinka postavlja
  odmah (računi su samo na tom uređaju). **Promjena lozinke** u Profilu.
- **Profil**: fotografija, ime, opis (do 160 znakova), grad, bedž ✓ *Provjeren* (potvrđen
  e-mail ili Google), **javni profil** s predmetima na prodaju, aukcijama i ocjenama.
- **Pozovi prijatelja**: kod za poziv je tvoje korisničko ime — oboje dobivate 100 LC.
- **Gost** samo razgledava; za kupnju, prodaju i ponude nudi se izrada računa.
- **Brisanje računa** (Profil → *Obriši račun*): prikaže što se gubi (krediti se ne mogu
  isplatiti), traži upis korisničkog imena i ne dopušta brisanje dok imaš aukciju s
  ponudama, vodeću (obvezujuću) ponudu ili pošiljku u tijeku. Račun se briše nakon
  **7 dana** — prijava u tom roku ga vraća. Postoji i *Obriši odmah*. U povijesti drugih
  umjesto imena piše `@obrisani`.
- **Preuzmi moje podatke**: svi tvoji podaci kao JSON datoteka (bez lozinki).

Lokalne lozinke spremaju se samo na uređaju kao sažetak (SHA-256 + sol), u boxu koji se
ne sinkronizira; online prijavu vodi Supabase Auth i lozinke ne prolaze kroz našu bazu.

## Objava u Marketu, poruke i zamjene

- **Novi predmet odmah ide u Market** (prekidač *Odmah objavi u Marketu* u obrascu je
  uključen). Predmeti koji su već bili u portfolijima jednom se automatski objave po svojoj
  cijeni (osim onih na aukciji); kasnije *Ukloni iz Marketa* se poštuje, a kupljeni
  predmeti se ne objavljuju sami. *Stavi na aukciju* predmet skida iz Marketa.
- **Objavi u Marketu**: vlastiti predmet po svojoj cijeni — ostaje tvoj dok ga netko ne
  kupi. Kupac plaća cijenu + 5%, ti dobivaš cijenu − 5%. **Ukloni iz Marketa** ili
  **Promijeni cijenu** u svakom trenutku; **Obriši predmet** ga trajno briše.
  Objava i aukcija se isključuju. *Prodaj odmah LOOP-u* i dalje radi kao prije.
- **Poruke**: na tuđem oglasu *Pošalji poruku* (poruka nosi karticu predmeta) ili s javnog
  profila; ikona 💬 u gornjoj traci pokazuje nepročitane.
- **Ponudi zamjenu**: tvoj predmet (+ nadoplata u kreditima) za tuđi objavljeni predmet.
  Vlasnik prihvaća ili odbija; nakon prihvaćanja predmeti mijenjaju vlasnike, nadoplata
  ide vlasniku (− 5%), a oboje biraju dostavu u *Moje dostave*.

## Digitalni proizvodi (3D modeli, softver, e-knjige…)

- Odjeljak **Digitalno**: 3D modeli, softver, e-knjige i tečajevi, predlošci i grafika,
  glazba i zvukovi.
- Prodavatelj u *Dodaj predmet* odabere *Digitalno* i **učita datoteku** (STL, OBJ, 3MF,
  STEP, ZIP, PDF, EPUB, PNG, SVG, MP3… — bez izvršnih datoteka; softver kao .zip;
  najviše 25 MB online). Stanje se ne bira, a proizvod odmah ide u Market.
- Digitalni proizvod se **prodaje više puta**: prodavatelj ga zadržava, svaki kupac plaća
  cijenu + 5%, prodavatelj dobiva cijenu − 5%. Nema dostave, aukcije, zamjene ni prodaje
  LOOP-u.
- Kupac **preuzima datoteku odmah** nakon plaćanja, a kasnije u *Profil → Moje digitalne
  kupnje* ili na stranici proizvoda. Isti kupac ne plaća dvaput.
- Vlasnik vidi broj kupaca, može preuzeti i **zamijeniti datoteku** (nova verzija vrijedi i
  za postojeće kupce). Proizvod s kupcima ne može se obrisati — samo ukloniti iz Marketa.
- Online su datoteke u **privatnom** Supabase bucketu `loop-files`; pravila u bazi dopuštaju
  preuzimanje samo vlasniku i kupcima (`supabase/schema.sql`). Lokalno su na uređaju.
- Demo: *Kocka za kalibraciju* (STL) i *Predložak plakata* (SVG) od LOOP-a.

## Ocjene, obavijesti, prijave i blokiranje

- **Ocjene**: nakon potvrde primitka kupac ocjenjuje prodavatelja (1–5 ★ + komentar).
  Prosjek je na javnom profilu i na oglasu.
- **Obavijesti** (🔔 u gornjoj traci): nadmašen si na aukciji, nova ponuda, osvojena /
  izgubljena / završena aukcija, prodan predmet, pojeftinjenje s liste želja, nova ocjena,
  nova poruka, ponuda zamjene, bonus za poziv. Tekst je na jeziku korisnika; dodir vodi
  na aukciju, predmet, profil ili razgovor.
- **Prijava** oglasa ili korisnika (razlog + opis) — admin ih vidi u kartici *Prijave* i
  briše sadržaj, označava riješenim ili odbacuje.
- **Blokiranje**: oglasi i aukcije blokiranog se ne prikazuju, a on ti ne može slati
  poruke, kupovati tvoje predmete ni licitirati na tvojim aukcijama.

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
   (Pokreni ga ponovno nakon nadogradnje aplikacije — postojeći podaci ostaju.)
3. **Project Settings → API**: kopiraj **Project URL** i **Publishable key**
   (`sb_publishable_…`; u starijim projektima *anon public* ključ).
4. **Authentication → URL Configuration**: *Site URL* = adresa web linka
   (`https://karlo6546541.github.io/bot/`), isto i u *Redirect URLs*.
5. **Authentication → Sign In / Providers → Email**: za testiranje isključi
   *Confirm email* (ugrađeni Supabase e-mail šalje samo nekoliko poruka na sat). Ako ga
   ostaviš uključenog, novi korisnik mora otvoriti link iz e-maila prije prve prijave.
6. **Google prijava** (neobavezno):
   1. https://console.cloud.google.com → novi projekt → **APIs & Services → OAuth consent
      screen** (External, naziv aplikacije, e-mail) → **Credentials → Create credentials →
      OAuth client ID → Web application**.
   2. *Authorized redirect URIs*: `https://TVOJ-PROJEKT.supabase.co/auth/v1/callback`.
   3. Kopiraj **Client ID** i **Client secret** u Supabase → **Authentication → Sign In /
      Providers → Google** → uključi → Save.

> ⚠️ Testna shema: čitati smiju svi, pisati samo prijavljeni korisnici. Pravila trgovanja
> (krediti, ponude) i dalje provjerava aplikacija, ne server — koristi samo izmišljene
> podatke. Vidi *Put do produkcije*.

### 2. Pokretanje aplikacije spojene na bazu

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://TVOJ-PROJEKT.supabase.co `
  --dart-define=SUPABASE_KEY=sb_publishable_TVOJ_KLJUC
```

Prvi prijavljeni klijent na praznoj bazi pošalje u nju demo podatke, a svi sljedeći ih
preuzmu. Online se prijavljuje e-mailom i lozinkom (ili Googleom); demo računi
(`demo@loop.com` …) postoje samo lokalno. *Profil* prikazuje stanje veze (🟢 povezano / 🟠 nedostupno / ⚪ lokalno).
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
- RLS pravila po korisniku (prijava već ide preko Supabase Autha): svatko piše samo svoje
  podatke, a tuđe mijenjaju isključivo funkcije na serveru;
- **kupnje, ponude, dopune i zaključivanje aukcija kao funkcije na serveru** (Postgres
  funkcije ili Edge Functions), koje u jednoj transakciji provjeravaju kredite i pravila,
  da ih klijent ne može zaobići i da dvije istovremene kupnje istog predmeta ne prođu;
- pravila za Storage po korisniku (svatko briše samo svoje slike) i provjeru veličine/vrste
  na serveru;
- zaključivanje aukcija i statuse dostava putem zakazanog posla (cron) na serveru.

---

## Demo podaci za login

Lokalni način (bez online baze):

| Uloga    | E-mail / ime                        | Lozinka    | Napomena                                          |
|----------|-------------------------------------|------------|---------------------------------------------------|
| Korisnik | `demo@loop.com` / `@demo`           | `demo`     | 1 250 LC + iPhone 13 i Laptop Lenovo → **Silver** |
| Korisnik | `test@loop.com` / `@test`           | `demo`     | 800 LC, prazan portfolio → **Bronze**             |
| Admin    | `admin@loop.com`                    | `admin123` | preko gumba **"Admin prijava"**                   |
| Gost     | —                                   | —          | **"Samo razgledaj (gost)"** — bez kupnje/prodaje  |
| Korisnik | `ana@loop.com` / `@ana.kolekcija`   | `demo`     | prodaje 4 predmeta na aukcijama                   |
| Korisnik | `marko@loop.com` / `@marko`         | `demo`     | vodi na 3 aukcije (470 LC blokirano)              |

Novi račun: *Registracija* (e-mail, korisničko ime, lozinka) → **500 LC** početnih kredita.
Računi iz starijih verzije: prva lozinka kojom se prijaviš postaje lozinka računa.

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
- **Objava u Marketu** (od korisnika): kupac plaća `cijena × 1.05`, prodavatelj dobiva
  `cijena × 0.95`.
- **Zamjena**: nadoplatu plaća ponuditelj, vlasnik dobiva `nadoplata × 0.95`.
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
│                             # PortfolioPoint, UserStatus, Review, AppNotification, Report,
│                             # ChatMessage, SwapOffer
├── services/
│   ├── storage_service.dart  # Hive pohrana (users, devices, transactions, session)
│   ├── trade_service.dart    # prodaja, kupnja, objava u Marketu, brisanje, admin akcije
│   ├── account_service.dart  # registracija, prijava, korisničko ime, profil, brisanje računa
│   ├── auth_backend.dart     # lokalne lozinke (sažeci) ili Supabase Auth (+ Google)
│   ├── username_rules.dart   # pravila i prijedlozi korisničkih imena
│   ├── community_service.dart# ocjene, prijave, blokiranje, pročitane obavijesti
│   ├── chat_service.dart     # poruke između korisnika
│   ├── swap_service.dart     # zamjene predmet-za-predmet
│   ├── inbox.dart            # stvaranje obavijesti
│   ├── file_saver/           # spremanje datoteke (preuzimanje na webu)
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
├── admin/                    # admin panel: dashboard, korisnici, uređaji, transakcije, prijave
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
hrvatski i engleski format iznosa, promjenu teme i **jezika** (svaki tekst ima prijevod),
**pravila aukcija** (blokiranje i povrat kredita, obvezujuće ponude, limit kredita,
produljenje, zaključivanje), **račune** (registracija, lozinke, jedinstveno korisničko
ime, promjena imena, kod za poziv, Google prijava bez imena, brisanje računa i izvoz),
**objave u Marketu**, **ocjene, obavijesti, prijave i blokiranje**, **poruke i zamjene**,
admin akcije i reset te UI tokove (registracija, gost, prodaja i kupnja, objava i brisanje,
obavijesti, poruke, brisanje računa) na desktop i mobilnoj širini.
