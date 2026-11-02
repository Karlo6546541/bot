# Subhasto: marketinška strategija za lansiranje

Stranica: `https://karlo6546541.github.io/bot/site/` (lista čekanja, demo videi).
Prijave se spremaju u Supabase, tablica `waitlist` (izravno nedostupna javnosti; upis i
mjesto na listi idu kroz funkcije `waitlist_join`, `waitlist_status`, `waitlist_count`).

## 1. Pozicioniranje u jednoj rečenici

**"Licitiraj uživo. Pobijedi za 30 sekundi."**

Njuškalo i Facebook grupe su spori i puni pregovaranja; eBay aukcija traje sedam dana.
Subhasto je **brz, zabavan i siguran**: prodavač pokaže predmet na kameri, licitacija traje
sekunde, plaćanje i dostava idu kroz aplikaciju, kupac dobije broj za praćenje.

Ne natječemo se cijenom nego **uzbuđenjem** (live, odbrojavanje, "PRODANO!") i
**povjerenjem** (zaštita kupca, prodavač šalje, jasna provizija).

## 2. Kome se obraćamo (redom)

1. **Kolekcionari** (Pokémon/TCG kartice, retro igre, sneakersi, satovi, vinil, LEGO,
   numizmatika). Već kupuju u FB grupama i na Instagram "storyjima", navikli su na
   licitacije u komentarima. Najbrže prihvaćaju live aukcije.
2. **Mali prodavači i "ormar" prodavači** (vintage odjeća, rabljena elektronika).
   Glavna poruka: *jedan live od sat vremena = tjedan oglasa*.
3. **Digitalni kreatori** (predlošci, 3D modeli, presetovi): Kupi odmah u liveu,
   preuzimanje odmah.

Pravilo: **prvo osvojiti jednu nišu** (preporuka: TCG kartice + sneakersi u Zagrebu),
tek onda širiti. Live tržnica bez prodavača je prazna soba.

## 3. Glavni motor rasta: lista čekanja koja se sama širi

- Svaka prijava dobije **osobni link**. Svaki prijatelj koji se upiše preko njega pomiče
  osobu **jedan dan naprijed** u redu (pravedno: ranije prijave i dalje imaju prednost).
- Na stranici se vidi **broj ljudi koji čeka** (socijalni dokaz) i **tvoje mjesto** kad se
  vratiš.
- Dijeljenje jednim dodirom: WhatsApp, kopiraj link, sustavno dijeljenje na mobitelu.
- **Pozivanje u valovima**: kad pokrećemo, prvi val su oni najviše na listi. "Ulaziš u
  prvi val" je jača nagrada od popusta.

### Odluke koje su na tebi (namjerno nisu obećane na stranici)
- **Osnivački prodavači**: npr. prvih 50 prodavača 0 % provizije 3 mjeseca + oznaka
  "Osnivač" na profilu. Snažno privlači prodavače, ali je trošak: odluči prije objave.
- **Nagrada za top preporučitelje**: npr. 20 € kredita za prvih 10 po broju preporuka.
- Kad odlučiš, dodaj to u odjeljak "Lista čekanja" na stranici (`site/index.html`).

## 4. Sadržaj: 5 gotovih videa (9:16, MP4)

U `site/media/`, spremni za Reels, TikTok i Shorts:

| Video | Udica (prve 2 s) | Za koga |
|---|---|---|
| `subhasto-live-aukcija.mp4` | "Licitacija traje 30 sekundi." | svi |
| `subhasto-items-on-screen.mp4` | "Prodavač pokaže kartu. Ti je uzmeš." | TCG kolekcionari |
| `subhasto-community-boost.mp4` | "Podijeli live, digni ga na vrh." | gledatelji |
| `subhasto-dostava.mp4` | "Ne biraš dostavu. Samo pratiš paket." | oprezni kupci |
| `subhasto-pada-cijena.mp4` | "Cijena pada. Tko prvi, njegovo." | lovci na popuste |

Svaki završava pozivom na listu čekanja i adresom stranice. Uz videe preporuka:

- **Pravi prodavači snimaju sebe** (lice + predmet + "PRODANO!"). Takav sadržaj na TikToku
  radi bolje od bilo kakve animacije. Prvih 5 prodavača zamoli za 3 kratka videa.
- **Serijal "Koliko je prodano?"**: pokaži predmet, pogađaj cijenu, otkrij koliko je
  završio na liveu. Komentari = doseg.
- **Objavljivanje**: 1 video dnevno, 18–21 h (kad se gleda), isti video na TikTok, Reels,
  Shorts.

## 5. Kanali (od najjeftinijeg)

1. **Facebook grupe kolekcionara** (TCG, sneakersi, retro igre, satovi): ne spamati, nego
   ponuditi adminima **prvi live u njihovoj grupi** (admin je domaćin, članovi licitiraju).
2. **Instagram/TikTok** s gornjim videima + suradnje s 5–10 mikro-influencera (2–20 tisuća
   pratitelja) iz niše: plaća se proizvodom ili postotkom prodaje, ne gotovinom.
3. **Discord/Reddit** zajednice (r/croatia, TCG Discordi): AMA "radimo hrvatski Whatnot".
4. **Sajmovi i turniri** (TCG turniri, sneaker eventi, sajam antikviteta): QR kod na listu
   čekanja + "uživo licitiramo s tvog štanda".
5. **Lokalni mediji / startup portali**: priča "hrvatska aplikacija za live aukcije".

## 6. Lansiranje u 4 faze

| Faza | Trajanje | Cilj | Mjerilo |
|---|---|---|---|
| 0. Lista čekanja | 3–4 tjedna | 1 000 prijava, 50 prodavača | prijave/dan, udio preko preporuka |
| 1. Zatvoreni val | 2 tjedna | 10 prodavača, 3 showa tjedno | gledatelji po showu, prodaja po showu |
| 2. Javni start u niši | 4 tjedna | dnevni live u 18–22 h | ponovni kupci, vrijeme gledanja |
| 3. Širenje | dalje | nove kategorije, cijela HR | broj prodavača koji se vraćaju |

**Raspored showova** je ključan: gledatelji moraju znati *kad* je nešto uživo.
Npr. pon TCG, sri sneakersi, pet "retro petak", ned vintage moda.

## 7. Mjerila koja stvarno prate uspjeh

- **Udio prijava preko preporuka** (cilj > 30 %; ako je manje, nagrada je preslaba).
- **Prodavači koji naprave drugi show** (najvažnije za tržnicu).
- **Gledatelji po showu** i **udio gledatelja koji licitiraju**.
- **Ponovni kupci u 30 dana**.

Stanje liste čekanja možeš pratiti SQL upitom u Supabaseu:

```sql
select role, count(*) from waitlist group by role;
select count(*) filter (where referred_by is not null) * 100.0 / count(*) as posto_preko_preporuka from waitlist;
select email, referrals from waitlist order by referrals desc limit 20;
```

## 8. Što još treba prije javne kampanje

- **Uvjeti i privatnost** za listu čekanja (e-mail se koristi samo za obavijest o
  pokretanju; dodaj kontakt za brisanje).
- **Slanje e-maila** pri pokretanju (npr. Resend ili Brevo) iz tablice `waitlist`.
- **Vlastita domena** (npr. `subhasto.hr`) umjesto GitHub adrese; promijeni i tekst u
  videima (`site/reel.html`) pa ih ponovno snimi.
