# Uključivanje online livea i Stripe testne naplate

Kod je u grani `improve/subhasto-live-backend`, PR #13. Novi tok otvara se iz
izbornika gore desno → **Live i trgovina online** nakon uključivanja zastavice.
Postojeće demo objave i narudžbe ostaju odvojene.

## 1. Supabase baza

Projekt: `mwhrjrxytfdttjjdhdns`. U SQL Editoru izvrši redom:

1. `migrations/001_live.sql`
2. `migrations/002_commerce.sql`
3. `migrations/003_payments.sql`

Javni publishable ključ ne dopušta izvršavanje tih migracija. Potreban je pristup
SQL Editoru ili lokalno prijavljen Supabase CLI. Lozinku baze i admin ključeve ne
šalji kroz chat i ne stavljaj u repozitorij.

## 2. Vanjske usluge i tajne

Otvori projekt na https://cloud.livekit.io i Stripe račun na
https://dashboard.stripe.com/register. Stripe koristi isključivo u testnom načinu.
U Supabase → Edge Functions → Secrets postavi:

| Naziv | Vrijednost |
|---|---|
| LIVEKIT_URL | `wss://…livekit.cloud` iz projekta |
| LIVEKIT_API_KEY | LiveKit API ključ |
| LIVEKIT_API_SECRET | LiveKit tajni ključ |
| STRIPE_SECRET_KEY | Stripe testni ključ `sk_test_…` |
| STRIPE_WEBHOOK_SECRET | Tajna webhooka `whsec_…` |
| APP_ORIGIN | `https://karlo6546541.github.io` |
| APP_URL | `https://karlo6546541.github.io/bot/` |

Supabase osigurava vlastiti URL, anon i service-role ključ unutar funkcija.
Nijedan tajni ključ ne ide u Flutter build ili GitHub Pages.

## 3. Edge Functions

Iz `functions/` postavi `live-token`, `live-control`, `stripe-connect`,
`stripe-checkout`, `stripe-webhook` i zajedničku mapu `_shared`.
Postavke provjere JWT-a su u `config.toml`: funkcije same provjeravaju identitet,
a webhook provjerava Stripeov potpis nad izvornim tijelom zahtjeva.

U Stripe testnom dashboardu dodaj webhook za `checkout.session.completed` na:

`https://mwhrjrxytfdttjjdhdns.supabase.co/functions/v1/stripe-webhook`

Tajnu tog webhooka spremi u Supabase secrets.

## 4. Uključi i provjeri

Kad je kod iz PR-a #13 spojen i servisi postavljeni, postavi GitHub Actions repository variable
`CLOUD_COMMERCE_ENABLED=true`. Pokreni workflow `LOOP web (GitHub Pages)`.

Provjeri s dva testna računa i jednim gostom:

- Gost otvara live i vidi chat; komentar i ponuda otvaraju prijavu.
- Voditelj pokreće live, dopušta kameru/mikrofon i dodaje predmet.
- Drugi račun vidi video, šalje komentar i daje ponudu.
- Voditelj utišava/zabranjuje korisnika; zabrana prekida i SFU vezu.
- Pobjednik potvrđuje rezultat, otvara narudžbu i bira paketomat.
- Prodavatelj završava Stripe Express testni onboarding.
- Kupac plaća u Stripe hosted checkoutu testnom karticom.
- Tek potvrđeni webhook mijenja narudžbu u plaćenu.
- Prodavatelj unosi praćenje; kupac potvrđuje primitak.

Prijenos je trenutačno implementiran za web. Nova native LiveKit integracija,
automatsko zatvaranje/oporavak naplate i rezervacija, povrati, obračun/isplate i
stvarne dostavne naljepnice ostaju za sljedeću fazu. Ručna potvrda primitka nije
potvrda prijevoznika. Cijena checkouta zasad sadrži predmet bez dostavnih/tax
naknada. Za taj kod nisu provedena testiranja stvarnih pružatelja jer računi i
serverski ključevi nisu dostupni u radnom okruženju.
