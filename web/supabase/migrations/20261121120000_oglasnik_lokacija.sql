-- Lokacija oglasa: država (ISO kod), županija/regija (neobavezna izvan Hrvatske)
-- i grad. Tablica je na produkciji još prazna, pa je promjena bez rizika.

alter table public.oglasnik_oglasi
  add column if not exists drzava text not null default 'HR'
  check (drzava ~ '^[A-Z]{2}$');

-- Županija je obavezna samo u Hrvatskoj (to provjerava aplikacija); drugdje je
-- slobodna "regija" ili prazno.
alter table public.oglasnik_oglasi alter column zupanija drop not null;
alter table public.oglasnik_oglasi drop constraint if exists oglasnik_oglasi_zupanija_check;
alter table public.oglasnik_oglasi
  add constraint oglasnik_oglasi_zupanija_check
  check (zupanija is null or char_length(zupanija) between 2 and 60);

alter table public.oglasnik_profili
  add column if not exists drzava text not null default 'HR'
  check (drzava ~ '^[A-Z]{2}$');

-- Tekst za pretragu sada uključuje i županiju (stupac se mora napraviti iznova).
alter table public.oglasnik_oglasi drop column if exists pretraga;
alter table public.oglasnik_oglasi add column pretraga text generated always as (
  translate(
    lower(naslov || ' ' || opis || ' ' || grad || ' ' || coalesce(zupanija, '') || ' ' || polja::text),
    'čćžšđáàäâéèëêíìïîóòöôúùüûýÿñ', 'cczsdaaaaeeeeiiiioooouuuuyyn')
) stored;
create index if not exists oglasnik_oglasi_pretraga on public.oglasnik_oglasi
  using gin (pretraga extensions.gin_trgm_ops);
create index if not exists oglasnik_oglasi_lokacija on public.oglasnik_oglasi (drzava, zupanija, grad);

-- Grad bez dijakritike i velikih slova, za filter ("sibenik" nalazi "Šibenik").
alter table public.oglasnik_oglasi add column if not exists grad_n text generated always as (
  translate(lower(grad), 'čćžšđáàäâéèëêíìïîóòöôúùüûýÿñ', 'cczsdaaaaeeeeiiiioooouuuuyyn')
) stored;
create index if not exists oglasnik_oglasi_grad_n on public.oglasnik_oglasi (drzava, grad_n);
