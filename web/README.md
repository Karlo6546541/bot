# Subhasto web (Next.js)

Oglasnik za kolekcionare s poslužiteljskim iscrtavanjem (SSR/ISR) radi SEO-a:
svaki oglas je prava HTML stranica s naslovom, opisom, canonical adresom,
Open Graph slikom i strukturiranim podacima (Product/Offer, BreadcrumbList).
Backend je Supabase (tablice `oglasnik_*`, isti projekt kao Flutter aplikacija).

## Lokacija oglasa
Država (ISO kod, npr. `HR`), županija i grad. Županija je obavezna u Hrvatskoj
(popis od 21 županije), a izvan nje je slobodna "regija" ili prazno. Filtriranje
po državi, županiji i gradu (grad bez dijakritike: "sibenik" nalazi "Šibenik")
radi na popisu i u kategorijama, a stranice s filterima nisu u indeksu (noindex).

## Dizajn
Isti kao Flutter aplikacija (boje, Inter, Material ikone, donja traka/bočna traka, pločice, kategorije). Kategorije se generiraju iz Flutter koda: `python3 scripts/generiraj_kategorije.py <flutter>/packages/flutter/lib/src/material/icons.dart`.

## Pokretanje
    npm ci
    cp .env.example .env.local   # URL i ključ Supabasea
    npm run dev
    npm run typecheck && npm test          # logika + SQL (PGlite)
    node smoke/mock-supabase.mjs &          # lažna baza na :54321
    npm run build && npx next start -p 3100 &
    npm run smoke                           # HTML, SEO, lokacije, mobitel

## Varijable okruženja
| Varijabla | Opis |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_KEY` | Supabase (publishable/anon ključ) |
| `NEXT_PUBLIC_SITE_URL` | javna adresa (canonical, sitemap, OAuth povratak) |
| `NEXT_PUBLIC_APP_NAME`, `NEXT_PUBLIC_APP_SLOGAN`, `NEXT_PUBLIC_CONTACT_EMAIL` | ime, slogan, kontakt |

## Baza
Migracije su u `supabase/migrations/` (prva je već na produkciji; druga dodaje
`drzava`, nullable `zupanija`, `grad_n` za pretragu i indekse). Admin:

    update public.oglasnik_profili set admin = true where id = '<uuid korisnika>';

## Deploy (Vercel)
Projekt `subhasto-oglasnik` (tim `team_pGtb1D774SqwHdGH1O7loOvu`, id `prj_0MzUigf5eGIpj6VrnFue382OM1Is`)
povezan je s ovim repozitorijem: root directory `web`, framework Next.js, Node 22,
varijable `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_KEY` i `NEXT_PUBLIC_APP_NAME`.
Svaki push na granu daje preview deployment. Produkcijska grana projekta je trenutno
`claude/polymarket-btc-trading-bot-t3qqvt`; promijeni je u `main` (Settings → Git)
kad oglasnik ide u produkciju. Zaštita deploymenta (Vercel prijava) je uključena
dok se ne objavi javno (Settings → Deployment Protection).
Google prijava: uključi Google provider u Supabaseu i dodaj
`https://<domena>/auth/callback` u dopuštene redirect adrese.

## Selidba na vlastitu domenu (npr. subhasto.com)
1. Domena se kupuje u Vercelu (Domains) ili kod drugog registrara.
2. Vercel → projekt `subhasto-oglasnik` → Settings → Domains: dodaj `subhasto.com` i `www.subhasto.com`
   (www preusmjerava na glavnu). Kod vanjskog registrara upiši DNS zapise koje Vercel pokaže
   (A `76.76.21.21` za glavnu, CNAME `cname.vercel-dns.com` za www).
3. Varijabla `NEXT_PUBLIC_SITE_URL=https://subhasto.com` (canonical, sitemap, hreflang) i novi deploy.
4. Supabase → Authentication → URL Configuration: Site URL `https://subhasto.com`, dodaj
   `https://subhasto.com/auth/callback` u Redirect URLs (Google prijava i potvrda e-maila).
5. Google Cloud OAuth: dodaj `https://subhasto.com` u Authorized JavaScript origins.
6. Google Search Console: dodaj domenu i pošalji `https://subhasto.com/sitemap.xml`.

## Objava i vidljivost
Oglas se sprema u `oglasnik_oglasi` i odmah je vidljiv svima: nakon objave/izmjene web zove
`/api/osvjezi`, koji osvježava keširane stranice (početna, kategorije, oglas) na oba jezika.
Oglasi iz Flutter aplikacije stižu preko okidača u bazi i vidljivi su najkasnije za 60 s.
