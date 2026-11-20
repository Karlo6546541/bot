# Oglasnik za kolekcionare (Subhasto)

Jednostavan oglasnik: korisnik objavi oglas, drugi ga pronađe i kontaktira
prodavatelja porukom (ili telefonom). Cijena, plaćanje i preuzimanje
dogovaraju se izvan aplikacije. Aukcije i plaćanje su u arhivi:
grana `arhiva/v0-aukcije` (i oznaka `v0-aukcije`), stara aplikacija je
objavljena na `/bot/v0-aukcije/`.

## Pokretanje

    npm ci
    npm run dev          # lokalno, bez baze (demo način u IndexedDB-u)
    npm test             # logika, lokalni backend i SQL (PGlite)
    npm run build && npm run e2e   # kriteriji prihvaćanja u Chromiumu (375 px)

S bazom: `.env.local` s `VITE_SUPABASE_URL` i `VITE_SUPABASE_KEY` (anon /
publishable ključ).

## Gdje se što mijenja

- Ime, slogan, istek oglasa, broj slika: `src/config/app.ts` ili varijable
  `VITE_APP_NAME`, `VITE_APP_SLOGAN`, `VITE_CONTACT_EMAIL`.
- Kategorije, dodatna polja po kategoriji, stanja, županije, razlozi prijave:
  `src/config/kategorije.ts`.
- Baza (tablice `oglasnik_*`, RLS, bucket `oglasnik-slike`):
  `supabase/migrations/20261120120000_oglasnik.sql`.

## Administrator

    update public.oglasnik_profili set admin = true where id = '<uuid korisnika>';

(u Supabase SQL editoru, nakon što se korisnik prvi put prijavi).
