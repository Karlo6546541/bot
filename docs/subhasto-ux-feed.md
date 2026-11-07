# Subhasto: UX i preporuke

Izvorna verzija: `a75b2f2fbbb73fc3966d124983bab9e7cd37a6a8`.
Sigurnosna grana: `backup/subhasto-before-ux-feed-20261027`.

## Ponašanje

- Mobilna početna ima kompaktnu navigaciju Pratim / Za tebe / Uživo i pretragu.
  Aukcije, Kupi odmah i Uskoro dostupni su kroz Filtere. Poruke i obavijesti
  dostupne su i u tom izborniku te u zaglavlju ostalih kartica.
- Okomito povlačenje mijenja oglas, vodoravno fotografiju. Brojač pokazuje
  trenutnu fotografiju, povećalo otvara postojeći pregled s uvećavanjem.
- Slika i opis otvaraju isti panel detalja. Cijena, stanje, početni trošak
  dostave i ocjena prodavača vidljivi su prije kupnje. Konačni način i cijena
  dostave potvrđuju se u postojećoj blagajni. Novčanik se ne prikazuje na svakoj objavi.
- Izbornik ⋯ omogućuje Manje ovakvog, skrivanje oglasa ili prodavača i vraćanje
  skrivenih sadržaja. Preferencije i povijest gledanja ostaju lokalne i odvojene
  po računu; ne mijenjaju se javni oglasi niti praćenje prodavača.
- Vrijeme gledanja akumulira se samo dok je aplikacija aktivna i feed vidljiv.
  Drugi tab, detalji, modalni paneli i aplikacija u pozadini pauziraju mjerenje.
- Oglasi iz zadnja 24 sata ne ponavljaju se automatski. Završni ekran omogućuje
  provjeru novih objava, izričito ponovno gledanje i uređivanje preporuka.
- Preporuke koriste budžet po kategoriji, model i stanje pregledanih predmeta,
  raznolikost prodavača te povremeno otkrivanje novih oglasa. Red se obrađuje
  u manjim skupinama, uz ograničenu povijest listanja.

## Provjera

Workflow `Subhasto UX and feed checks` pokreće formatiranje, `flutter analyze`,
`flutter test` i release web build. Ne objavljuje stranicu. Postojeći Pages workflow
nastavlja objavljivati iz grane `claude/beautiful-newton-sftcyd`.

Novi testovi pokrivaju vidljivo vrijeme, trajnost i odvajanje preferencija po
računu, povijest prikazivanja, skrivanje sadržaja, budžet po kategoriji i galeriju.
Postojeći testovi navigacije prilagođeni su izborniku Filteri i panelu detalja.
