// Predlošci pravnih dokumenata (HR/EN). Podatke u [uglatim zagradama]
// treba zamijeniti stvarnim podacima tvrtke, a tekst dati na pregled
// odvjetniku prije pokretanja s pravim novcem.

/// Podaci o pružatelju usluge (impresum) — zamijeniti stvarnima.
const kCompany = '[NAZIV TVRTKE d.o.o.]';
const kCompanyOib = '[OIB]';
const kCompanyAddress = '[ADRESA SJEDIŠTA]';
const kCompanyEmail = '[KONTAKT E-MAIL]';
const kCompanyCourt = '[TRGOVAČKI SUD, MBS]';
const kDocsDate = '[DATUM]';

const legalHr = <String, String>{
  'terms':
      '''
Ovi Uvjeti uređuju korištenje platforme LOOP (aplikacija i web stranica) koju pruža $kCompany, OIB $kCompanyOib, $kCompanyAddress ("LOOP", "mi"). Registracijom potvrđuješ da imaš najmanje 18 godina i da prihvaćaš ove Uvjete i Pravila privatnosti.

## 1. Što je LOOP
LOOP je online tržnica (marketplace) na kojoj korisnici međusobno kupuju i prodaju predmete po fiksnoj cijeni, na aukciji ili zamjenom. LOOP nije prodavatelj predmeta: ugovor o kupoprodaji sklapaju kupac i prodavatelj.

## 2. Računi
LOOP mogu koristiti samo punoljetne fizičke osobe, za osobne potrebe (ne kao obrt ni tvrtka) — i kao kupci i kao prodavatelji. Jedna osoba smije imati jedan račun. Podaci moraju biti točni. Odgovoran si za sigurnost lozinke. Račun možeš obrisati u Profilu (brisanje se izvršava nakon 7 dana).

## 3. Prodavatelji
Prodavatelji su fizičke osobe koje prodaju svoje stvari. Prije prve objave unose podatke prodavatelja (ime i prezime, OIB, datum rođenja, adresu, IBAN). Tko prodaje kao djelatnost (obrt, tvrtka), ne smije koristiti LOOP. Zabranjeni predmeti navedeni su u Pravilima za prodavatelje.

## 4. Cijene i naknade
Kupac plaća cijenu predmeta uvećanu za naknadu platforme od 2 % (prikazana cijena je konačna) te dostavu ako je odabrana. Prodavatelj dobiva punu cijenu oglasa. Objava aukcije i isticanje računa naplaćuju se prema cijeni prikazanoj prije potvrde.

## 5. Plaćanje i isplata
Plaćanje karticom i isplate prodavateljima obrađuje licencirani pružatelj platnih usluga ([NAZIV PRUŽATELJA, npr. Mangopay ili Stripe]). LOOP ne drži novac korisnika. Zarada prodavatelja isplaćuje se na IBAN iz podataka prodavatelja.

## 6. Aukcije
Ponuda na aukciji je obvezujuća i ne može se povući dok te netko ne nadmaši. Automatska ponuda licitira umjesto tebe do iznosa koji odrediš. Ponuda u zadnjoj minuti produljuje aukciju za minutu. Pobjednik plaća najvišu ponudu karticom nakon završetka aukcije.

## 7. Ponude za cijenu i zamjene
Prihvaćena ponuda za cijenu vrijedi 48 sati. Zamjena se izvršava kad je obje strane prihvate.

## 8. Pravo na povrat
Svi prodavatelji su privatne osobe, pa zakonsko pravo na odustanak od 14 dana ne postoji. Kupac ima pravo na predmet kakav je opisan u oglasu; ako stigne bitno drukčiji ili ne stigne, prijavi problem prije potvrde primitka.

## 9. Zabranjeni sadržaj i moderacija
Nezakonit sadržaj i oglasi protivni ovim Uvjetima mogu se prijaviti gumbom "Prijavi". Ako ograničimo tvoj sadržaj ili račun, dobit ćeš obrazloženje i mogućnost žalbe (Akt o digitalnim uslugama).

## 10. Rangiranje i oglašavanje
Kako određujemo redoslijed oglasa i što znači oznaka "Sponzorirano" objašnjeno je u dokumentu Rangiranje i oglašavanje.

## 11. Odgovornost
LOOP odgovara za rad platforme, ali ne za stanje, opis ili isporuku predmeta koje prodaju korisnici. Sporove između kupca i prodavatelja pokušavamo riješiti kroz prijave i komunikaciju.

## 12. Izmjene i pravo
O izmjenama Uvjeta obavještavamo najmanje 15 dana unaprijed. Primjenjuje se pravo Republike Hrvatske; potrošači zadržavaju zaštitu prava države prebivališta. Platforma za online rješavanje sporova: https://ec.europa.eu/consumers/odr.

Vrijedi od: $kDocsDate
''',
  'privacy':
      '''
Voditelj obrade: $kCompany, OIB $kCompanyOib, $kCompanyAddress, $kCompanyEmail.

## Koje podatke obrađujemo
- Račun: e-mail, korisničko ime, lozinka (samo sažetak), profilna slika, opis, grad.
- Prodavatelji: ime ili naziv, OIB, datum rođenja, adresa, IBAN, vrsta prodavatelja.
- Trgovanje: oglasi, kupnje, prodaje, aukcije, ponude, zamjene, dostave, ocjene, poruke, priče, liste želja.
- Tehnički: osnovni zapisi potrebni za rad i sigurnost.

## Zašto i na kojoj osnovi
- Izvršenje ugovora: račun, oglasi, kupnje, dostava, poruke.
- Zakonska obveza: podaci prodavatelja za DAC7 (izvještaj Poreznoj upravi), računovodstvo.
- Legitimni interes: sigurnost, sprječavanje prijevara, moderacija.

## Primatelji
Pružatelj baze podataka i hostinga ([npr. Supabase, regija EU]), pružatelj plaćanja ([NAZIV]), dostavne službe (samo za tvoju pošiljku), Porezna uprava (DAC7). Podatke ne prodajemo.

## Koliko dugo
Dok imaš račun; nakon brisanja računa podaci se brišu, osim onih koje zakon traži čuvati (npr. transakcije i podaci za DAC7 do 10 godina).

## Tvoja prava
Pristup, ispravak, brisanje, ograničenje, prenosivost (izvoz podataka u Profilu) i prigovor. Pritužbu možeš podnijeti Agenciji za zaštitu osobnih podataka (azop.hr).

Vrijedi od: $kDocsDate
''',
  'cookies': '''
LOOP koristi samo nužnu lokalnu pohranu preglednika i aplikacije:
- prijava (sesija) i sigurnost,
- postavke (jezik, tema),
- podaci aplikacije za rad bez mreže.

Ne koristimo kolačiće za praćenje, analitiku ni oglašavanje, pa za nužnu pohranu nije potreban pristanak. Ako to promijenimo, prije uključivanja tražit ćemo tvoj pristanak.

Pohranu možeš obrisati u postavkama preglednika (tada ćeš biti odjavljen).
''',
  'imprint':
      '''
Pružatelj usluge: $kCompany
Sjedište: $kCompanyAddress
OIB: $kCompanyOib
Upis: $kCompanyCourt
Temeljni kapital: [IZNOS] €, uplaćen u cijelosti
Uprava: [IME I PREZIME]
Kontakt: $kCompanyEmail
Kontakt točka za korisnike i tijela (DSA): $kCompanyEmail
''',
  'sellerRules': '''
## Tko može prodavati
Punoljetne fizičke osobe s ispunjenim podacima prodavatelja koje prodaju svoje stvari. Obrti i tvrtke ne mogu prodavati na LOOP-u.

## Zabranjeno je prodavati
Oružje i streljivo, drogu i lijekove na recept, krivotvorine, ukradene predmete, žive životinje, opasne tvari, sadržaj za odrasle, osobne isprave, predmete koji krše tuđa autorska ili žigovna prava te sve što je zabranjeno zakonom.

## Oglas mora biti
Točan (stanje, fotografije vlastitog predmeta), s pravom cijenom. Popust se smije prikazati samo uz stvarnu prethodnu cijenu (prikazujemo najnižu cijenu u zadnjih 30 dana).

## Porez (DAC7)
Prodavatelje s 30 ili više prodaja ili više od 2.000 € godišnje platforma prijavljuje Poreznoj upravi.
''',
  'ranking': '''
## Redoslijed "Preporučeno"
Oglasi se slažu prema: isticanju trgovine (plaćeno, označeno "Sponzorirano"), praćenim trgovinama, popularnosti (pregledi, sviđanja), svježini oglasa i ocjeni prodavatelja. Možeš odabrati i drugi poredak (najnovije, cijena, naziv).

## Sponzorirano
Trgovina može platiti isticanje računa na tjedan dana. Njezini oglasi tada se prikazuju više i uvijek su označeni kao "Sponzorirano". Plaćanje ne utječe na ocjene ni na sigurnosne provjere.

## Ocjene
Ocjene kupaca koji su kupili od prodavatelja označene su "✓ Provjerena kupnja"; ostale ocjene trgovine označene su "Bez provjerene kupnje". Ocjene ne uklanjamo zbog toga što su negativne.
''',
  'reporting': '''
## Prijava nezakonitog sadržaja
Na svakom oglasu, profilu i poruci je gumb "Prijavi". Navedi razlog; prijavu pregledava moderator.

## Odluka i obrazloženje
Ako uklonimo sadržaj ili ograničimo račun, dobit ćeš obavijest s razlogom i pravilom na koje se odluka oslanja.

## Žalba
Na odluku se možeš žaliti u roku od 6 mjeseci gumbom "Žalba" u obavijesti. Žalbu pregledava druga osoba. Imaš pravo i na izvansudsko rješavanje spora te na sudsku zaštitu.
''',
};

const legalEn = <String, String>{
  'terms':
      '''
These Terms govern the use of the LOOP platform (app and website) provided by $kCompany, OIB $kCompanyOib, $kCompanyAddress ("LOOP", "we"). By registering you confirm that you are at least 18 years old and accept these Terms and the Privacy Policy.

## 1. What LOOP is
LOOP is an online marketplace where users buy and sell items from each other at a fixed price, at auction or by swapping. LOOP is not the seller: the sales contract is between buyer and seller.

## 2. Accounts
LOOP may only be used by adult natural persons for personal purposes (not as a sole trader or company) — both as buyers and as sellers. One person may have one account. Your details must be accurate. You are responsible for your password. You can delete your account in Profile (deletion happens after 7 days).

## 3. Sellers
Sellers are natural persons selling their own things. Before the first listing they provide seller details (full name, OIB/tax number, date of birth, address, IBAN). Anyone selling as a business (sole trader, company) may not use LOOP. Prohibited items are listed in the Seller rules.

## 4. Prices and fees
The buyer pays the item price plus a 2% platform fee (the displayed price is final) and delivery if chosen. The seller receives the full listing price. Auction listing and account promotion are charged at the price shown before confirmation.

## 5. Payment and payouts
Card payments and seller payouts are processed by a licensed payment service provider ([PROVIDER NAME, e.g. Mangopay or Stripe]). LOOP does not hold users' money. Seller earnings are paid out to the IBAN in the seller details.

## 6. Auctions
A bid is binding and cannot be withdrawn until you are outbid. Automatic bidding bids for you up to the amount you set. A bid in the last minute extends the auction by a minute. The winner pays the highest bid by card after the auction ends.

## 7. Price offers and swaps
An accepted price offer is valid for 48 hours. A swap is executed when both sides accept.

## 8. Right of withdrawal
All sellers are private persons, so there is no statutory 14-day right of withdrawal. The buyer is entitled to the item as described in the listing; if it arrives substantially different or does not arrive, report the problem before confirming receipt.

## 9. Prohibited content and moderation
Illegal content and listings breaching these Terms can be reported with "Report". If we restrict your content or account, you will receive a statement of reasons and can appeal (Digital Services Act).

## 10. Ranking and advertising
How we order listings and what "Sponsored" means is explained in Ranking and advertising.

## 11. Liability
LOOP is responsible for operating the platform, not for the condition, description or delivery of items sold by users. We try to resolve disputes between buyers and sellers through reports and communication.

## 12. Changes and law
We announce changes to these Terms at least 15 days in advance. Croatian law applies; consumers keep the protection of their country of residence. EU online dispute resolution: https://ec.europa.eu/consumers/odr.

Effective from: $kDocsDate
''',
  'privacy':
      '''
Controller: $kCompany, OIB $kCompanyOib, $kCompanyAddress, $kCompanyEmail.

## What we process
- Account: e-mail, username, password (hash only), profile photo, bio, city.
- Sellers: name or company name, OIB, date of birth, address, IBAN, seller type.
- Trading: listings, purchases, sales, auctions, offers, swaps, deliveries, reviews, messages, stories, wishlists.
- Technical: basic logs needed for operation and security.

## Why and on what basis
- Contract: account, listings, purchases, delivery, messages.
- Legal obligation: seller details for DAC7 (report to the Tax Administration), accounting.
- Legitimate interest: security, fraud prevention, moderation.

## Recipients
Database and hosting provider ([e.g. Supabase, EU region]), payment provider ([NAME]), delivery services (only for your parcel), Tax Administration (DAC7). We do not sell data.

## How long
While you have an account; after deletion data is erased, except what the law requires us to keep (e.g. transactions and DAC7 data for up to 10 years).

## Your rights
Access, rectification, erasure, restriction, portability (data export in Profile) and objection. You may lodge a complaint with the Croatian Personal Data Protection Agency (azop.hr).

Effective from: $kDocsDate
''',
  'cookies': '''
LOOP only uses strictly necessary local storage in the browser and app:
- login (session) and security,
- settings (language, theme),
- app data for offline use.

We do not use tracking, analytics or advertising cookies, so no consent is needed for necessary storage. If this changes, we will ask for your consent first.

You can clear storage in your browser settings (you will be logged out).
''',
  'imprint':
      '''
Service provider: $kCompany
Registered office: $kCompanyAddress
OIB: $kCompanyOib
Registration: $kCompanyCourt
Share capital: [AMOUNT] €, fully paid
Management: [NAME]
Contact: $kCompanyEmail
Point of contact for users and authorities (DSA): $kCompanyEmail
''',
  'sellerRules': '''
## Who can sell
Adult natural persons with completed seller details selling their own things. Sole traders and companies cannot sell on LOOP.

## It is prohibited to sell
Weapons and ammunition, drugs and prescription medicines, counterfeits, stolen goods, live animals, hazardous substances, adult content, identity documents, items infringing copyright or trademarks, and anything prohibited by law.

## A listing must be
Accurate (condition, photos of your own item), with a real price. A discount may only be shown against a genuine previous price (we show the lowest price in the last 30 days).

## Tax (DAC7)
The platform reports sellers with 30 or more sales or more than €2,000 per year to the Tax Administration.
''',
  'ranking': '''
## "Recommended" order
Listings are ordered by: shop promotion (paid, labelled "Sponsored"), shops you follow, popularity (views, likes), freshness and seller rating. You can choose another order (newest, price, name).

## Sponsored
A shop can pay to promote its account for a week. Its listings are then shown more often and are always labelled "Sponsored". Payment does not affect ratings or safety checks.

## Reviews
Reviews from buyers who bought from the seller are marked "✓ Verified purchase"; other shop ratings are marked "No verified purchase". We do not remove reviews for being negative.
''',
  'reporting': '''
## Reporting illegal content
Every listing, profile and message has a "Report" button. State the reason; a moderator reviews the report.

## Decision and statement of reasons
If we remove content or restrict an account, you will receive a notification with the reason and the rule the decision relies on.

## Appeal
You can appeal within 6 months with the "Appeal" button in the notification. A different person reviews the appeal. You also have the right to out-of-court dispute settlement and to judicial redress.
''',
};
