# LOOP — Trade. Don't sell.

Demo Flutter aplikacija: zatvorena trading platforma za rabljene uređaje
(mobiteli, laptopi, tableti, slušalice, konzole).

- Svi iznosi i stanje računa su u **eurima** (€).
- **Prodaja je besplatna** — prodavatelj dobiva punu cijenu. **Kupac plaća 2% naknade.**
- Svaki račun je istovremeno i kupac i prodavatelj.
- Novi računi počinju s **0 €** (nema poklona pri registraciji); novac se uplaćuje (u demo verziji simulirano).
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
  hrvatski: „1.250 €”, „294,50 €”; engleski „€1,250”.
- **Uplata novca (demo):** iznosi 50 / 100 / 250 / 500 / 1000 € ili vlastiti iznos (10–2000 €),
  bez bonusa. Načini plaćanja: kartica, Apple Pay, Google Pay, PayPal.
  **Ništa se stvarno ne naplaćuje i ne unose se podaci kartice.** Dnevni limit uplata je 2000 €.
  Dostupno s početne („Uplati novac”), iz trake sa stanjem gore desno, iz Profila te
  automatski kad za kupnju ili ponudu nema dovoljno novca.
- **Početna:** brze akcije (Uplati novac, Dodaj predmet, Market, Aukcije) i kartica „Kako LOOP
  radi” koja se može zatvoriti.
- **Aukcije:** objavi predmet iz svog portfolija (početna cijena i trajanje od 2 min do 7 dana),
  ostali licitiraju. Pravila:
  - ponuda je **obvezujuća** i ne može se povući ni smanjiti;
  - vodeći ponuđač ne može dati novu ponudu dok ga netko ne nadmaši;
  - ponuda ne može biti **veća od raspoloživog stanja**;
  - iznos vodeće ponude se **blokira** na računu i vraća se čim te netko nadmaši;
  - najmanji korak je 5% trenutne cijene;
  - ponuda u zadnjoj minuti produljuje aukciju za 1 minutu;
  - na kraju pobjednik dobiva predmet, a prodavatelj cijelu najvišu ponudu (aukcije su bez naknade);
  - bez ponuda predmet ostaje prodavatelju, koji aukciju može otkazati samo dok nema ponuda.

  **Protiv masovnog stavljanja svega na aukcije** (`lib/services/auction_policy.dart`):
  - najviše 4 aktivne aukcije po korisniku;
  - najviše 3 nove aukcije u 24 sata;
  - na aukciju idu samo predmeti vrijedni barem 50 € (sitnice → Market);
  - naknada za objavu: 2% vrijednosti predmeta (najmanje 2 €), ne vraća se;
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
- **Grafikon portfolija:** vrijednost (stanje + predmeti) kroz vrijeme s rasponima 7D/30D/Sve,
  crosshair i tooltip na prelazak mišem ili dodir, te tablični prikaz istih podataka.
- **Portfolio:** animirano stanje, traka napretka do sljedećeg statusa i raspodjela po
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
  e-mailom (lokalno i korisničkim imenom). Novi računi počinju s 0 €.
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
- **Pozovi prijatelja**: kod za poziv je tvoje korisničko ime (bez novčanog bonusa — dobivaš obavijest kad se netko registrira s tvojim kodom).
- **Gost** samo razgledava; za kupnju, prodaju i ponude nudi se izrada računa.
- **Brisanje računa** (Profil → *Obriši račun*): prikaže što se gubi (preostalo stanje — u demo
  verziji nema isplate), traži upis korisničkog imena i ne dopušta brisanje dok imaš aukciju s
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
  kupi. Kupac plaća cijenu + 2%, ti dobivaš punu cijenu. **Ukloni iz Marketa** ili
  **Promijeni cijenu** u svakom trenutku; **Obriši predmet** ga trajno briše.
  Objava i aukcija se isključuju. *Prodaj odmah LOOP-u* i dalje radi kao prije.
- **Poruke**: na tuđem oglasu *Pošalji poruku* (poruka nosi karticu predmeta) ili s javnog
  profila; ikona 💬 u gornjoj traci pokazuje nepročitane.
- **Ponudi zamjenu**: tvoj predmet (+ nadoplata u eurima) za tuđi objavljeni predmet.
  Vlasnik prihvaća ili odbija; nakon prihvaćanja predmeti mijenjaju vlasnike, nadoplata
  ide vlasniku u cijelosti (ponuditelj plaća + 2%), a oboje biraju dostavu u *Moje dostave*.

## Trgovina, pretraga i kupljene stvari

- **Trgovina (javni profil)**: naslovna slika s profilnom slikom preko ruba, brojke
  (pratitelji, prati, prodaje, oglasi), *Prati* i *Poruka*, te kartice **Trgovina /
  Aukcije / Ocjene**.
- **Kategorije trgovine** nastaju same: svaki objavljeni predmet ulazi u svoju kategoriju,
  a iznad oglasa je filtar (Sve, Mobiteli (2), Kamere (1)…), uz pretragu i sortiranje.
- **Pretraga** (ikona povećala gore ili polje na početnoj): kartice **Objave** (oglasi i
  aukcije, otvaraju se u swipe feedu) i **Računi** (trgovine po korisničkom imenu, nazivu
  trgovine, gradu ili opisu), uz povijest pretraga.
- **Kupljeno ide u portfolio**: kupljeni predmet prelazi kupcu i nestaje iz Marketa;
  kupljeni digitalni proizvodi više se ne prikazuju u tvom Marketu, nego u portfoliju
  (oznaka „✓ Kupljeno”, gumb *Preuzmi*).
- **Ponuda cijene** se upisuje u donjem listu koji se podigne iznad tipkovnice.
- **Moj profil** je podijeljen u odjeljke: Moja trgovina, Novac i kupnje, Račun, Postavke.

## Aukcije: automatska ponuda, Kupi odmah, zvono

- **Licitiranje u jednom listu** (gumb *Licitiraj* na aukciji ili u swipe feedu): brzi
  iznosi, vlastiti iznos i **automatska ponuda** — upišeš najviše koliko si spreman dati,
  a aukcija licitira umjesto tebe najmanjim korakom (5%) do tog iznosa. Blokira se samo
  trenutna vodeća ponuda. Vodeći može povisiti svoj maksimum.
- **Kupi odmah**: prodavatelj pri objavi može upisati cijenu kojom kupac odmah osvaja
  predmet (dok ponude ne dosegnu tu cijenu); vodeća ponuda se vraća.
- **Zvono (prati aukciju)**: obavijest 10 minuta prije kraja (i onima koji su licitirali).
- **Pratitelji trgovine** dobiju obavijest kad trgovina pokrene aukciju.
- Aukcije su i u **swipe feedu** (oznaka 🔨 s odbrojavanjem, trenutna cijena, broj ponuda,
  *Licitiraj*, zvono) i u mreži objava na početnoj.

## Objave kao TikTok, trgovine i pratitelji

- Swipe feed: slika preko cijelog ekrana (zamućena pozadina za uske/široke fotografije),
  dolje trgovina s gumbom *Prati*, naziv i opis, a desno stupac akcija — nikad se ne
  preklapaju. Jedan glavni gumb: *Kupi · cijena* ili *Licitiraj*. Dvostruki dodir = lajk,
  dodir na sliku = detalji. Na računalu objava ima oblik mobitela.
- **Naslovna i profilna slika trgovine** mijenjaju se dodirom na ikonu kamere na vlastitom
  profilu (galerija, kamera ili ukloni).

- **Početna** odmah ispod stanja: gumb **Gledaj objave**, „Trgovine za tebe” i mreža
  **objava** (oglasi drugih prodavatelja, nasumičnim redom, s prednošću za trgovine koje
  pratiš, istaknute račune, popuste i popularne trgovine).
- Dodir na objavu otvara **swipe feed preko cijelog ekrana** (gore/dolje kao TikTok):
  avatar prodavatelja s **+ (Prati)**, **♥ lajk** (broj lajkova = koliko ljudi ima predmet u
  favoritima; dvostruki dodir lajka), **Ponudi** cijenu, **Podijeli**, **broj prikaza**, te
  *Kupi* i *Detalji*. Market ostaje klasičan popis s filterima.
- **Svaki račun je webshop**: kartica „Tvoja trgovina” na početnoj, zaslon **Trgovine**
  (Market → *Trgovine* ili *Sve trgovine*) s pretragom i redoslijedom (pratitelji, ocjena,
  prodaje, oglasi), filter *Samo trgovine koje pratim*.
- **Pratitelji**: na profilu i trgovini su brojevi *pratitelja*, *prati/pratim* i *prodaja* —
  dodir otvara popis pratitelja / koga prati, odnosno popis prodaja.
- **Ocjena trgovine** zvjezdicama s profila trgovine (*Ocijeni*); jedna ocjena po korisniku,
  može se promijeniti. Ulazi u prosjek zajedno s ocjenama kupnji.
- **Dijeljenje** otvara sistemski izbornik (WhatsApp, Instagram, Viber, SMS…) na mobitelu
  (i u pregledniku na mobitelu); na računalu izbornik s WhatsAppom, Viberom, Instagramom,
  Facebookom, Telegramom, X-om, SMS-om, e-mailom i kopiranjem poveznice.
- Online: prikazi su u tablici `loop_views` — pokreni ponovno `supabase/schema.sql`.

## Mini webshop, cjenkanje, popusti i praćenje

- **Količina na zalihi**: pri objavi (i u *Cijena i zaliha*) upisuješ broj komada. Svaka
  kupnja skida jedan komad — kupac dobiva svoj primjerak, oglas ostaje dok se ne proda
  zadnji komad (tada prodavatelj dobiva obavijest *Rasprodano*).
- **Popust** na oglas: 5–90%, trajno ili 1 / 3 / 7 / 30 dana. Cijena se prikazuje crveno uz
  prekriženu redovnu cijenu i oznaku „−20%”; u Marketu postoji filter **Na popustu**.
  Pratitelji i oni kojima je predmet na listi želja dobiju obavijest.
- **Ponudi cijenu (cjenkanje)**: kupac nudi iznos (najmanje 30% cijene); prodavatelj
  **prihvaća**, **odbija** ili daje **protuponudu**, a kupac prihvaća ili odbija
  protuponudu. Dogovorena cijena vrijedi **48 sati** i samo za tog kupca — gumb *Kupi*
  tada naplaćuje dogovorenu cijenu. Sve ponude: *Profil → Ponude cijena*.
- **Prati** prodavatelja (na oglasu ili trgovini): obavijest o novim oglasima i popustima,
  a njegovi oglasi su prvi u feedu *Za tebe* na početnoj.
- **Mini webshop**: javni profil je trgovina — naziv trgovine (*Profil → Naziv trgovine*),
  pratitelji, broj prodaja, pretraga i sortiranje oglasa (najnovije, cijena, popust).
- **Dijeljenje**: ikona dijeljenja na oglasu i trgovini kopira poveznicu
  (`…/bot/?item=<id>` ili `…/bot/?shop=<korisnik>`); poveznica otvara oglas/trgovinu
  nakon prijave.
- **Feed *Za tebe*** na početnoj: praćeni prodavatelji, istaknuti računi, popusti, novo.
- **Top prodavatelji**: ljestvica po broju prodaja (tjedan / mjesec / ukupno).
- **Isticanje računa** (*Profil → Istakni račun*): 4,99 € tjedno — oglasi su prvi u Marketu
  (sortiranje *Preporučeno*) i u feedu, s oznakom „⭐ Istaknuto”.
- **Pretraga**: povijest pretraga (zadnjih 10, na uređaju), pretraga računa/trgovina po
  imenu, a „c/s/z/d/dj” pronalaze i „č/ć/š/ž/đ”.
- Online: ponude cijena su u tablici `loop_bargains` — pokreni ponovno `supabase/schema.sql`.

## Raspored sučelja

- Donja traka: **Početna · Market · [+ Objavi] · Aukcije · Profil**.
  **+ Objavi** nudi *Oglas*, *Aukciju* ili *Priču* (jedno mjesto za sve).
- **Početna**: stanje (dodir na "Ukupno…" otvara *Moje predmete*), priče,
  objave i trgovine. Grafikon vrijednosti, raspodjela i popis predmeta su
  na ekranu **Moji predmeti** (i Profil → Moja trgovina).
- **Profil**: *Moja trgovina* (statistika, moji predmeti, trgovina,
  ponude cijena, isticanje) · *Novac i kupnje* (stanje i uplata, povijest
  transakcija, dostave, digitalne kupnje, liste želja) · *Račun* · *Postavke*.
- Srce na oglasu = "Sviđa mi se"; obavijest nudi *Spremi u listu*.
  Spremanje i prijava oglasa su u izborniku ⋮.
- Market: pretraga, gumb **Filteri** i odjeljci; moji oglasi su na kraju
  s oznakom *Tvoj oglas*.
- Spremljena kopija verzije prije ovog rasporeda: `/bot/stara/`
  (gradi se iz commita `fc5bf8d` uz glavnu verziju).

## Obavijesti

- Filteri: **Sve · Aukcije · Kupnje i prodaje · Ponude · Društvo · Poruke**
  (s brojem nepročitanih), podjela po danima (Danas, Jučer, Ovaj tjedan,
  Ranije). Više obavijesti o istoj aukciji spaja se u jednu karticu.
- Kartica aukcije: slika predmeta, odbrojavanje, trenutna cijena, oznaka
  *Vodiš ✓* / *Nadmašen* i gumb **Licitiraj / Povisi ponudu** (otvara list
  za ponudu) ili **Odaberi dostavu** kad si pobijedio. Filter *Aukcije*
  ima sažetak: koliko aukcija vodiš, gdje si nadmašen i koliko ih prodaješ.
- Povlačenje ulijevo briše obavijest; gumb ✓✓ označava sve kao pročitano.
- **Postavke obavijesti** (ikona gore desno): isključi "Netko me nadmašio",
  "Nove ponude na mojim aukcijama", "Aukcija uskoro završava", "Nove aukcije
  trgovina koje pratim", pojeftinjenja, oglase trgovina i nove pratitelje.
  Rezultati aukcija, prodaje, ponude za cijenu i poruke stižu uvijek.
  Postavke se spremaju uz korisnika (bez nove tablice).

## Liste želja i priče (stories)

- **Liste želja**: na oglasu (ikona oznake) ili u objavama ("Spremi") predmet
  se sprema u jednu ili više imenovanih lista (naziv + simbol, npr. 🏠 Za stan).
  "Sviđa mi se" je ugrađena lista lajkova. Profil → *Liste želja* prikazuje
  kartice s mozaikom predmeta; lista se može preimenovati, obrisati i
  **podijeliti** poveznicom `?list=<korisnik>.<lista>`. Prodani predmeti
  ostaju na listi s oznakom *Prodano*. Liste se spremaju uz korisnika
  (do 20 lista, 100 predmeta po listi).
- **Priče** traju 24 sata: tekst na boji, fotografija i/ili vlastiti oglas
  (s cijenom i gumbom *Pogledaj*).
- **Urednik priče** (kao na Instagramu): dodir na pozadinu ili *Aa* dodaje
  tekst (do 6). Tekst se **povlači po pozadini** (vodilice za sredinu),
  dva prsta ga povećavaju i rotiraju, a povlačenjem u kantu briše se.
  Pri upisu: 5 fontova (Klasično, Moderno, Neon, Pisaći stroj, Rukopis),
  9 boja, poravnanje, pozadina teksta (bez / puna / poluprozirna) i
  klizač za veličinu. Gore su još boja pozadine, fotografija i oglas.
  Priča se prikazuje u omjeru 9:16, pa je tekst na istom mjestu kao u
  uredniku. Fontovi Bebas Neue, Space Mono i Pacifico su ugrađeni
  (SIL Open Font License, `assets/fonts/OFL-*.txt`). Red s pričama je na početnoj (praćene
  trgovine prve, pogledane na kraju — siv prsten), a prsten se vidi i oko
  profilne slike trgovine. Preglednik: dodir lijevo/desno, držanje pauzira,
  povlačenje dolje zatvara; svoju priču možeš obrisati. Demo trgovine Ana i
  Marko imaju dnevne priče koje se ne spremaju u bazu.
- Online baza: priče su u tablici `loop_stories` — nakon nadogradnje ponovno
  pokreni `supabase/schema.sql` (dok tablica ne postoji, priče su samo lokalne).

## Digitalni proizvodi (3D modeli, softver, e-knjige…)

- Odjeljak **Digitalno**: 3D modeli, softver, e-knjige i tečajevi, predlošci i grafika,
  glazba i zvukovi.
- Prodavatelj u *Dodaj predmet* odabere *Digitalno* i **učita datoteku** (STL, OBJ, 3MF,
  STEP, ZIP, PDF, EPUB, PNG, SVG, MP3… — bez izvršnih datoteka; softver kao .zip;
  najviše 25 MB online). Stanje se ne bira, a proizvod odmah ide u Market.
- Digitalni proizvod se **prodaje više puta**: prodavatelj ga zadržava, svaki kupac plaća
  cijenu + 2%, prodavatelj dobiva punu cijenu. Nema dostave, aukcije, zamjene ni prodaje
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
  nova poruka, ponuda zamjene, registracija s tvojim kodom. Tekst je na jeziku korisnika; dodir vodi
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
  (predmet + 2% naknade + dostava).
- **Aukcije:** pobjednik dobiva pošiljku koja čeka odabir dostave (*Profil → Moje dostave*
  ili traka na početnoj).

| Način | Cijena | Demo trajanje | Napomena |
|---|---|---|---|
| Osobno preuzimanje | besplatno | 2 min | LOOP točka |
| Paketomat | 3 € | 3 min | odabir paketomata |
| Kurir na adresu | 6 € | 4 min | adresa se pamti |
| Ekspresna dostava | 12 € | 2 min | |
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
| Korisnik | `demo@loop.com` / `@demo`           | `demo`     | 1.250 € + iPhone 13 i Laptop Lenovo           |
| Korisnik | `test@loop.com` / `@test`           | `demo`     | 800 €, prazan portfolio                        |
| Admin    | `admin@loop.com`                    | `admin123` | preko gumba **"Admin prijava"**                   |
| Gost     | —                                   | —          | **"Samo razgledaj (gost)"** — bez kupnje/prodaje  |
| Korisnik | `ana@loop.com` / `@ana.kolekcija`   | `demo`     | prodaje 4 predmeta na aukcijama                   |
| Korisnik | `marko@loop.com` / `@marko`         | `demo`     | vodi na 3 aukcije (470 € blokirano)               |

Novi račun: *Registracija* (e-mail, korisničko ime, lozinka) → stanje **0 €** (bez početnog poklona).
Računi iz starijih verzije: prva lozinka kojom se prijaviš postaje lozinka računa.

U Marketu je na početku 31 predmet: 12 iz elektronike (iPhone 15 Pro, MacBook Air M3,
Galaxy S24, iPad Air M2, AirPods Pro 2, iPhone 14, MacBook Pro 14", iPad Pro 11",
Apple Watch, Sony A7 III, PS5, Switch) i po 4–5 iz svakog novog odjeljka.

**Resetiranje:** *Profil → "Resetiraj demo podatke"* briše sve i vraća početno stanje.

---

## Poslovna pravila

- Postoje samo **kupci i prodavatelji** — nema više „LOOP Marketa” ni prodaje platformi.
  Stari predmeti platforme automatski dobiju demo prodavatelje (@ana.kolekcija, @marko,
  @test) i objave se po svojoj cijeni.
- **Prodavatelj ne plaća naknadu** i dobiva punu cijenu oglasa.
- **Kupac vidi jednu cijenu** u koju je uračunata naknada platforme od 2% (oglas 100 € →
  kupac vidi i plaća 102 €). Naknada se kupcu ne prikazuje kao zasebna stavka; prodavatelj
  pri objavi vidi „Kupci vide cijenu …” i „Ti dobivaš …”.
- Popust i dogovorena cijena (cjenkanje) smanjuju cijenu oglasa.
- **Aukcije**: pobjednik plaća svoju ponudu, prodavatelj dobiva cijeli iznos.
- **Zamjena**: nadoplatu plaća ponuditelj (+ 2%), vlasnik dobiva cijelu nadoplatu.
- **Isticanje računa**: 4,99 € tjedno (1–4 tjedna), plaća se sa stanja.

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
│   ├── auction_service.dart  # aukcije: objava, ponude, blokiranje iznosa, zaključivanje
│   ├── credit_shop.dart      # uplata novca: iznosi, dnevni limit (demo)
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
