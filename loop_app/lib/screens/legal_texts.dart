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
Ovi Uvjeti uređuju korištenje platforme Subhasto (aplikacija i web stranica) koju pruža $kCompany, OIB $kCompanyOib, $kCompanyAddress ("Subhasto", "mi"). Registracijom potvrđuješ da prihvaćaš ove Uvjete i Pravila privatnosti.

## 1. Što je Subhasto
Subhasto je platforma za prodaju među građanima na tri načina: live aukcije (prodavatelj uživo pokazuje predmete i pokreće kratke licitacije, live traje dok je prodavatelj uživo), aukcije na vrijeme i Kupi odmah (fiksna cijena). Subhasto nije prodavatelj predmeta: ugovor o kupoprodaji sklapaju kupac (pobjednik aukcije) i prodavatelj.

## 2. Računi
Subhasto mogu koristiti fizičke osobe i trgovci (obrti i tvrtke) — i kao kupci i kao prodavatelji. Jedna osoba smije imati jedan račun. Podaci moraju biti točni. Odgovoran si za sigurnost lozinke. Račun možeš obrisati u Profilu (brisanje se izvršava nakon 7 dana).

## 3. Prodavatelji
Prodavatelj je privatna osoba (prodaje svoje rabljene stvari) ili trgovac (obrt ili tvrtka koja prodaje kao djelatnost). Prije prve objave na Kupi odmah i prije prve isplate zarade unosi podatke prodavatelja: privatna osoba ime i prezime, OIB, datum rođenja, adresu i IBAN; trgovac naziv obrta ili tvrtke, pravni oblik, OIB, sjedište, odgovornu osobu, e-mail i telefon za kupce, IBAN te po potrebi PDV broj i MBS/MBO, uz potvrdu da prodaje u skladu s propisima. Tko prodaje redovito radi zarade, mora se prijaviti kao trgovac. Kupci uz svaki oglas vide je li prodavatelj privatna osoba ili trgovac, a kod trgovca i njegove podatke za kontakt. Od trgovca kupac ima pravo na povrat u 14 dana od primitka i zakonsko jamstvo; od privatne osobe pravo na povrat ne vrijedi. Trgovci imaju veća ograničenja (do 200 aktivnih aukcija i 200 predmeta po liveu; privatne osobe 10 i 50). Zabranjeni predmeti navedeni su u Pravilima za prodavatelje.

## 4. Cijene i naknade
Kupac plaća samo cijenu predmeta (bez naknade platforme) i dostavu. Objava je besplatna. Prodavatelju se od isplate odbija provizija: kod Kupi odmah 5 % od cijene, a kod aukcija i live aukcija 10 % samo od razlike između prodajne i početne cijene (kod padajuće cijene — od najniže cijene); ako se predmet proda po početnoj cijeni, provizije nema.

## 5. Plaćanje i isplata
Plaćanje karticom i isplate prodavateljima obrađuje licencirani pružatelj platnih usluga ([NAZIV PRUŽATELJA, npr. Mangopay ili Stripe]). Subhasto ne drži novac korisnika. Zarada prodavatelja isplaćuje se na IBAN iz podataka prodavatelja.

## 6. Aukcije i live aukcije
Ponuda je obvezujuća i ne može se povući ni smanjiti. Prije prve ponude kupac sprema karticu i adresu za dostavu; pobjedniku se naplaćuje automatski, a pošiljka kreće na spremljenu adresu.
Aukcije na vrijeme: automatska ponuda licitira umjesto tebe do iznosa koji odrediš, a ponuda u zadnjoj minuti produljuje aukciju za minutu.
Live aukcije: domaćin pokreće licitaciju za jedan predmet u isto vrijeme. Ponuda je maksimalna ponuda — sustav licitira umjesto tebe za jedan korak iznad drugog najvišeg ponuđača, a kod jednakih ponuda vodi ranija. Koraci rastu s cijenom (1 € do 10 €, 2 € do 50 €, 5 € do 100 € i dalje). Svaka ponuda dok sat teče dodaje 2 sekunde. Na predmete koji tek dolaze može se predlicitirati. Kod padajuće cijene kupuje prvi koji potvrdi kupnju. Domaćin ne smije licitirati na svom liveu. Sve što kupac osvoji u istom liveu šalje se u jednom paketu, a dostava se plaća jednom. Neprodani predmeti mogu nakon livea automatski prijeći u Kupi odmah po početnoj cijeni.

## 7. Ponude za cijenu i zamjene
Prihvaćena ponuda za cijenu vrijedi 48 sati. Zamjena se izvršava kad je obje strane prihvate.

## 8. Pravo na povrat
Svi prodavatelji su privatne osobe, pa zakonsko pravo na odustanak od 14 dana ne postoji. Kupac ima pravo na predmet kakav je opisan u oglasu; ako stigne bitno drukčiji ili ne stigne, prijavi problem prije potvrde primitka.

## 9. Zabranjeni sadržaj i moderacija
Nezakonit sadržaj i oglasi protivni ovim Uvjetima mogu se prijaviti gumbom "Prijavi". Ako ograničimo tvoj sadržaj ili račun, dobit ćeš obrazloženje i mogućnost žalbe (Akt o digitalnim uslugama).

## 10. Rangiranje i oglašavanje
Kako određujemo redoslijed oglasa objašnjeno je u dokumentu Rangiranje i oglašavanje. Subhasto ne prodaje plaćeno isticanje.

## 11. Odgovornost
Subhasto odgovara za rad platforme, ali ne za stanje, opis ili isporuku predmeta koje prodaju korisnici. Sporove između kupca i prodavatelja pokušavamo riješiti kroz prijave i komunikaciju.

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
Subhasto koristi samo nužnu lokalnu pohranu preglednika i aplikacije:
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
Privatne osobe (svoje stvari) i trgovci — obrti i tvrtke — s ispunjenim podacima prodavatelja. Trgovac je jasno označen kod svakog oglasa, kupcima daje podatke za kontakt, pravo na povrat u 14 dana i jamstvo, a za proizvode odgovara prema propisima EU.

## Zabranjeno je prodavati
Oružje i streljivo, drogu i lijekove na recept, krivotvorine, ukradene predmete, žive životinje, opasne tvari, sadržaj za odrasle, osobne isprave, predmete koji krše tuđa autorska ili žigovna prava te sve što je zabranjeno zakonom.

## Oglas mora biti
Točan (stanje, fotografije vlastitog predmeta), s pravom cijenom. Popust se smije prikazati samo uz stvarnu prethodnu cijenu (prikazujemo najnižu cijenu u zadnjih 30 dana).

## Porez (DAC7)
Prodavatelje s 30 ili više prodaja ili više od 2.000 € godišnje platforma prijavljuje Poreznoj upravi.
''',
  'ranking': '''
## Redoslijed "Preporučeno"
Oglasi se slažu prema: praćenim trgovinama, popularnosti (pregledi, sviđanja), svježini oglasa i ocjeni prodavatelja. Možeš odabrati i drugi poredak (najnovije, cijena, naziv).

## Plaćeno isticanje
Nema ga — nitko ne može platiti da se njegovi oglasi prikazuju više.

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
These Terms govern the use of the Subhasto platform (app and website) provided by $kCompany, OIB $kCompanyOib, $kCompanyAddress ("Subhasto", "we"). By registering you accept these Terms and the Privacy Policy.

## 1. What Subhasto is
Subhasto is an auction platform: live auctions (the seller shows items live and starts short bidding rounds; a live show lasts as long as the seller is live) and timed auctions. Subhasto is not the seller: the sales contract is between the winning bidder and the seller.

## 2. Accounts
Subhasto may be used by private persons and traders (sole traders and companies) — both as buyers and as sellers. One person may have one account. Your details must be accurate. You are responsible for your password. You can delete your account in Profile (deletion happens after 7 days).

## 3. Sellers
A seller is either a private person (selling their own used things) or a trader (a sole trader or company selling as a business). Before the first Buy now listing and first payout they provide seller details: a private person their full name, OIB/tax number, date of birth, address and IBAN; a trader the business name, legal form, OIB, registered address, responsible person, email and phone for buyers, IBAN and, where applicable, VAT number and registry number, confirming they sell in line with the law. Anyone selling regularly for profit must register as a trader. Buyers see on every listing whether the seller is a private person or a trader, and for traders their contact details. Buying from a trader gives a 14-day right of withdrawal from delivery and the legal guarantee; buying from a private person does not include the right of withdrawal. Traders have higher limits (up to 200 active auctions and 200 items per live show; private persons 10 and 50). Prohibited items are listed in the Seller rules.

## 4. Prices and fees
The buyer pays only the item price (no platform fee) and delivery. Listing is free. A commission is deducted from the seller's payout: 5% of the price for Buy now, and for auctions and live auctions 10% only of the difference between the selling price and the starting price (for price-drop items, the lowest price); if an item sells at its starting price, there is no commission.

## 5. Payment and payouts
Card payments and seller payouts are processed by a licensed payment service provider ([PROVIDER NAME, e.g. Mangopay or Stripe]). Subhasto does not hold users' money. Seller earnings are paid out to the IBAN in the seller details.

## 6. Auctions and live auctions
A bid is binding and cannot be withdrawn or lowered. Before the first bid the buyer saves a card and a delivery address; the winner is charged automatically and the parcel ships to the saved address.
Timed auctions: automatic bidding bids for you up to the amount you set, and a bid in the last minute extends the auction by a minute.
Live auctions: the host starts bidding on one item at a time. A bid is a maximum bid — the system bids for you one increment above the second-highest bidder, and on equal bids the earlier one leads. Increments grow with the price (€1 up to €10, €2 up to €50, €5 up to €100 and so on). Every bid while the clock runs adds 2 seconds. Upcoming items can be pre-bid. On price-drop items, the first to confirm buys. The host may not bid in their own show. Everything a buyer wins in one show ships in one parcel, and delivery is paid once. Unsold items can automatically move to Buy now at their starting price after the show.

## 7. Price offers and swaps
An accepted price offer is valid for 48 hours. A swap is executed when both sides accept.

## 8. Right of withdrawal
All sellers are private persons, so there is no statutory 14-day right of withdrawal. The buyer is entitled to the item as described in the listing; if it arrives substantially different or does not arrive, report the problem before confirming receipt.

## 9. Prohibited content and moderation
Illegal content and listings breaching these Terms can be reported with "Report". If we restrict your content or account, you will receive a statement of reasons and can appeal (Digital Services Act).

## 10. Ranking and advertising
How we order listings is explained in Ranking and advertising. Subhasto does not sell paid promotion.

## 11. Liability
Subhasto is responsible for operating the platform, not for the condition, description or delivery of items sold by users. We try to resolve disputes between buyers and sellers through reports and communication.

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
Subhasto only uses strictly necessary local storage in the browser and app:
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
Private persons (their own things) and traders — sole traders and companies — with completed seller details. Traders are clearly labelled on every listing, give buyers contact details, a 14-day right of withdrawal and the legal guarantee, and are responsible for their products under EU law.

## It is prohibited to sell
Weapons and ammunition, drugs and prescription medicines, counterfeits, stolen goods, live animals, hazardous substances, adult content, identity documents, items infringing copyright or trademarks, and anything prohibited by law.

## A listing must be
Accurate (condition, photos of your own item), with a real price. A discount may only be shown against a genuine previous price (we show the lowest price in the last 30 days).

## Tax (DAC7)
The platform reports sellers with 30 or more sales or more than €2,000 per year to the Tax Administration.
''',
  'ranking': '''
## "Recommended" order
Listings are ordered by: shops you follow, popularity (views, likes), freshness and seller rating. You can choose another order (newest, price, name).

## Paid promotion
There is none — nobody can pay to have their listings shown more.

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
