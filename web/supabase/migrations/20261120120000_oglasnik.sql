-- Oglasnik za kolekcionare: tablice, pravila pristupa (RLS) i spremište slika.
-- Sve je u novim tablicama oglasnik_*; postojeće tablice (aukcije, narudžbe…)
-- se ne diraju. Admin se postavlja ručno:
--   update public.oglasnik_profili set admin = true where id = '<uuid korisnika>';

-- ---------- Profili ----------
create table if not exists public.oglasnik_profili (
  id uuid primary key references auth.users (id) on delete cascade,
  ime text not null check (char_length(ime) between 1 and 60),
  grad text check (grad is null or char_length(grad) <= 60),
  registriran timestamptz not null default now(),
  blokiran boolean not null default false,
  admin boolean not null default false
);

-- Telefon je privatan: čita ga samo vlasnik; drugima ga daje funkcija
-- oglasnik_telefon() i to samo kad je oglas tako označen.
create table if not exists public.oglasnik_privatno (
  id uuid primary key references auth.users (id) on delete cascade,
  telefon text check (telefon is null or char_length(telefon) <= 30)
);

create or replace function public.oglasnik_je_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select admin from public.oglasnik_profili where id = auth.uid()), false);
$$;

create or replace function public.oglasnik_je_aktivan_korisnik()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select not blokiran from public.oglasnik_profili where id = auth.uid()), false);
$$;

-- Korisnik ne smije sam sebi dati admina ni skinuti blokadu. Bez auth.uid()
-- (SQL editor, service role) promjene su dopuštene.
create or replace function public.oglasnik_profil_zastita()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.oglasnik_je_admin() then
    if tg_op = 'INSERT' then
      new.admin := false;
      new.blokiran := false;
      new.registriran := now();
    else
      new.admin := old.admin;
      new.blokiran := old.blokiran;
      new.registriran := old.registriran;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists oglasnik_profil_zastita on public.oglasnik_profili;
create trigger oglasnik_profil_zastita before insert or update on public.oglasnik_profili
  for each row execute function public.oglasnik_profil_zastita();

-- ---------- Oglasi ----------
create table if not exists public.oglasnik_oglasi (
  id uuid primary key default gen_random_uuid(),
  korisnik_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  naslov text not null check (char_length(naslov) between 3 and 100),
  kategorija text not null check (kategorija ~ '^[a-z0-9-]{2,40}$'),
  opis text not null check (char_length(opis) between 10 and 5000),
  cijena numeric(12, 2) check (cijena is null or (cijena >= 0 and cijena <= 10000000)),
  zupanija text not null check (char_length(zupanija) between 2 and 40),
  grad text not null check (char_length(grad) between 2 and 60),
  stanje text not null check (stanje in ('Novo', 'Kao novo', 'Dobro', 'Oštećeno')),
  polja jsonb not null default '{}'::jsonb check (jsonb_typeof(polja) = 'object'),
  slike text[] not null check (cardinality(slike) between 1 and 8),
  slike_male text[] not null check (cardinality(slike_male) = cardinality(slike)),
  prikazi_telefon boolean not null default false,
  -- Jedina vrsta prodaje; aukcije i plaćanje su u arhivi v0-aukcije.
  vrsta_prodaje text not null default 'fiksna_cijena' check (vrsta_prodaje = 'fiksna_cijena'),
  status text not null default 'aktivan' check (status in ('aktivan', 'prodano', 'uklonjen', 'obrisan')),
  objavljeno timestamptz not null default now(),
  azurirano timestamptz not null default now(),
  istjece timestamptz not null default now() + interval '30 days',
  prodano_datum timestamptz,
  prodano_cijena numeric(12, 2) check (prodano_cijena is null or prodano_cijena >= 0),
  uklonjeno_razlog text,
  -- Tekst za pretragu: mala slova bez dijakritike (isto radi i aplikacija).
  pretraga text generated always as (
    translate(lower(naslov || ' ' || opis || ' ' || grad || ' ' || polja::text),
      'čćžšđáàäâéèëêíìïîóòöôúùüûýÿñ', 'cczsdaaaaeeeeiiiioooouuuuyyn')
  ) stored
);
create index if not exists oglasnik_oglasi_popis on public.oglasnik_oglasi (status, istjece, objavljeno desc);
create index if not exists oglasnik_oglasi_kategorija on public.oglasnik_oglasi (kategorija, objavljeno desc);
create index if not exists oglasnik_oglasi_korisnik on public.oglasnik_oglasi (korisnik_id);
create extension if not exists pg_trgm with schema extensions;
create index if not exists oglasnik_oglasi_pretraga on public.oglasnik_oglasi
  using gin (pretraga extensions.gin_trgm_ops);

-- Pravila koja RLS ne može izraziti: tko smije mijenjati status, istek.
create or replace function public.oglasnik_oglas_zastita()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  je_admin boolean := auth.uid() is null or public.oglasnik_je_admin();
begin
  if tg_op = 'INSERT' then
    new.status := 'aktivan';
    new.objavljeno := now();
    new.istjece := now() + interval '30 days';
    new.prodano_datum := null;
    new.prodano_cijena := null;
    new.uklonjeno_razlog := null;
    new.vrsta_prodaje := 'fiksna_cijena';
  else
    new.id := old.id;
    new.korisnik_id := old.korisnik_id;
    new.objavljeno := old.objavljeno;
    if not je_admin then
      if old.status in ('uklonjen', 'obrisan') then
        raise exception 'Oglas se više ne može mijenjati.';
      end if;
      if new.status = 'uklonjen' then
        raise exception 'Samo administrator može ukloniti oglas.';
      end if;
      new.uklonjeno_razlog := old.uklonjeno_razlog;
      -- Produljenje: najviše 30 dana od sada.
      if new.istjece > now() + interval '30 days 5 minutes' then
        new.istjece := now() + interval '30 days';
      end if;
      if new.status = 'prodano' and old.status <> 'prodano' then
        new.prodano_datum := now();
      elsif new.status <> 'prodano' then
        new.prodano_datum := old.prodano_datum;
        new.prodano_cijena := old.prodano_cijena;
      end if;
    end if;
  end if;
  new.azurirano := now();
  return new;
end $$;
drop trigger if exists oglasnik_oglas_zastita on public.oglasnik_oglasi;
create trigger oglasnik_oglas_zastita before insert or update on public.oglasnik_oglasi
  for each row execute function public.oglasnik_oglas_zastita();

-- ---------- Favoriti ----------
create table if not exists public.oglasnik_favoriti (
  korisnik_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  oglas_id uuid not null references public.oglasnik_oglasi (id) on delete cascade,
  kreirano timestamptz not null default now(),
  primary key (korisnik_id, oglas_id)
);

-- ---------- Razgovori i poruke ----------
create table if not exists public.oglasnik_razgovori (
  id uuid primary key default gen_random_uuid(),
  oglas_id uuid not null references public.oglasnik_oglasi (id) on delete cascade,
  kupac_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  prodavatelj_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  kreirano timestamptz not null default now(),
  zadnja_poruka timestamptz not null default now(),
  kupac_procitao timestamptz,
  prodavatelj_procitao timestamptz,
  unique (oglas_id, kupac_id),
  check (kupac_id <> prodavatelj_id)
);
create index if not exists oglasnik_razgovori_prodavatelj on public.oglasnik_razgovori (prodavatelj_id);

create table if not exists public.oglasnik_poruke (
  id uuid primary key default gen_random_uuid(),
  razgovor_id uuid not null references public.oglasnik_razgovori (id) on delete cascade,
  posiljatelj_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  tekst text not null check (char_length(btrim(tekst)) between 1 and 2000),
  poslano timestamptz not null default now()
);
create index if not exists oglasnik_poruke_razgovor on public.oglasnik_poruke (razgovor_id, poslano);

-- ---------- Povijest kontakata (za statistiku) ----------
create table if not exists public.oglasnik_kontakti (
  id uuid primary key default gen_random_uuid(),
  oglas_id uuid not null references public.oglasnik_oglasi (id) on delete cascade,
  korisnik_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  vrsta text not null check (vrsta in ('poruka', 'telefon')),
  kreirano timestamptz not null default now()
);
create index if not exists oglasnik_kontakti_oglas on public.oglasnik_kontakti (oglas_id, kreirano desc);

-- Novi razgovor: prodavatelj se uzima iz oglasa, a kontakt se bilježi.
create or replace function public.oglasnik_razgovor_novi()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  o public.oglasnik_oglasi;
begin
  select * into o from public.oglasnik_oglasi where id = new.oglas_id;
  if o.id is null or o.status <> 'aktivan' or o.istjece <= now() then
    raise exception 'Oglas više nije aktivan.';
  end if;
  new.prodavatelj_id := o.korisnik_id;
  new.kreirano := now();
  new.zadnja_poruka := now();
  insert into public.oglasnik_kontakti (oglas_id, korisnik_id, vrsta)
    values (new.oglas_id, new.kupac_id, 'poruka');
  return new;
end $$;
drop trigger if exists oglasnik_razgovor_novi on public.oglasnik_razgovori;
create trigger oglasnik_razgovor_novi before insert on public.oglasnik_razgovori
  for each row execute function public.oglasnik_razgovor_novi();

create or replace function public.oglasnik_poruka_nova()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.oglasnik_razgovori r
     set zadnja_poruka = new.poslano,
         kupac_procitao = case when r.kupac_id = new.posiljatelj_id then new.poslano else r.kupac_procitao end,
         prodavatelj_procitao = case when r.prodavatelj_id = new.posiljatelj_id then new.poslano else r.prodavatelj_procitao end
   where r.id = new.razgovor_id;
  return new;
end $$;
drop trigger if exists oglasnik_poruka_nova on public.oglasnik_poruke;
create trigger oglasnik_poruka_nova after insert on public.oglasnik_poruke
  for each row execute function public.oglasnik_poruka_nova();

create or replace function public.oglasnik_procitano(p_razgovor uuid)
returns void language sql security definer set search_path = public as $$
  update public.oglasnik_razgovori
     set kupac_procitao = case when kupac_id = auth.uid() then now() else kupac_procitao end,
         prodavatelj_procitao = case when prodavatelj_id = auth.uid() then now() else prodavatelj_procitao end
   where id = p_razgovor and auth.uid() in (kupac_id, prodavatelj_id);
$$;

-- Telefon prodavatelja: samo prijavljenima, samo kad ga oglas prikazuje;
-- svaki prikaz bilježi se kao kontakt.
create or replace function public.oglasnik_telefon(p_oglas uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  o public.oglasnik_oglasi;
  tel text;
begin
  if auth.uid() is null or not public.oglasnik_je_aktivan_korisnik() then
    return null;
  end if;
  select * into o from public.oglasnik_oglasi where id = p_oglas;
  if o.id is null or not o.prikazi_telefon or o.status not in ('aktivan', 'prodano') then
    return null;
  end if;
  select telefon into tel from public.oglasnik_privatno where id = o.korisnik_id;
  if tel is not null and auth.uid() <> o.korisnik_id then
    insert into public.oglasnik_kontakti (oglas_id, korisnik_id, vrsta) values (p_oglas, auth.uid(), 'telefon');
  end if;
  return tel;
end $$;

-- ---------- Prijave oglasa ----------
create table if not exists public.oglasnik_prijave (
  id uuid primary key default gen_random_uuid(),
  oglas_id uuid not null references public.oglasnik_oglasi (id) on delete cascade,
  prijavitelj_id uuid not null references public.oglasnik_profili (id) on delete cascade,
  razlog text not null check (razlog in ('prevara', 'krivotvorina', 'neprimjereno', 'ostalo')),
  napomena text not null default '' check (char_length(napomena) <= 1000),
  kreirano timestamptz not null default now(),
  status text not null default 'otvorena' check (status in ('otvorena', 'rijesena')),
  unique (oglas_id, prijavitelj_id)
);

-- ---------- RLS ----------
alter table public.oglasnik_profili enable row level security;
alter table public.oglasnik_privatno enable row level security;
alter table public.oglasnik_oglasi enable row level security;
alter table public.oglasnik_favoriti enable row level security;
alter table public.oglasnik_razgovori enable row level security;
alter table public.oglasnik_poruke enable row level security;
alter table public.oglasnik_kontakti enable row level security;
alter table public.oglasnik_prijave enable row level security;

drop policy if exists profili_citaj on public.oglasnik_profili;
create policy profili_citaj on public.oglasnik_profili for select using (true);
drop policy if exists profili_novi on public.oglasnik_profili;
create policy profili_novi on public.oglasnik_profili for insert with check (id = auth.uid());
drop policy if exists profili_uredi on public.oglasnik_profili;
create policy profili_uredi on public.oglasnik_profili for update
  using (id = auth.uid() or public.oglasnik_je_admin());

drop policy if exists privatno_svoje on public.oglasnik_privatno;
create policy privatno_svoje on public.oglasnik_privatno for all
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists oglasi_citaj on public.oglasnik_oglasi;
create policy oglasi_citaj on public.oglasnik_oglasi for select using (
  status in ('aktivan', 'prodano')
  or (status = 'uklonjen' and korisnik_id = auth.uid())
  or public.oglasnik_je_admin()
);
drop policy if exists oglasi_novi on public.oglasnik_oglasi;
create policy oglasi_novi on public.oglasnik_oglasi for insert
  with check (korisnik_id = auth.uid() and public.oglasnik_je_aktivan_korisnik());
drop policy if exists oglasi_uredi on public.oglasnik_oglasi;
create policy oglasi_uredi on public.oglasnik_oglasi for update
  using ((korisnik_id = auth.uid() and public.oglasnik_je_aktivan_korisnik()) or public.oglasnik_je_admin());
-- Nema DELETE pravila: brisanje je status 'obrisan' (statistika ostaje).

drop policy if exists favoriti_svoje on public.oglasnik_favoriti;
create policy favoriti_svoje on public.oglasnik_favoriti for all
  using (korisnik_id = auth.uid()) with check (korisnik_id = auth.uid());

drop policy if exists razgovori_citaj on public.oglasnik_razgovori;
create policy razgovori_citaj on public.oglasnik_razgovori for select
  using (auth.uid() in (kupac_id, prodavatelj_id));
drop policy if exists razgovori_novi on public.oglasnik_razgovori;
create policy razgovori_novi on public.oglasnik_razgovori for insert
  with check (kupac_id = auth.uid() and public.oglasnik_je_aktivan_korisnik());

drop policy if exists poruke_citaj on public.oglasnik_poruke;
create policy poruke_citaj on public.oglasnik_poruke for select using (
  exists (select 1 from public.oglasnik_razgovori r
          where r.id = razgovor_id and auth.uid() in (r.kupac_id, r.prodavatelj_id))
);
drop policy if exists poruke_nova on public.oglasnik_poruke;
create policy poruke_nova on public.oglasnik_poruke for insert with check (
  posiljatelj_id = auth.uid()
  and public.oglasnik_je_aktivan_korisnik()
  and exists (select 1 from public.oglasnik_razgovori r
              where r.id = razgovor_id and auth.uid() in (r.kupac_id, r.prodavatelj_id))
);

drop policy if exists kontakti_citaj on public.oglasnik_kontakti;
create policy kontakti_citaj on public.oglasnik_kontakti for select using (
  public.oglasnik_je_admin()
  or exists (select 1 from public.oglasnik_oglasi o where o.id = oglas_id and o.korisnik_id = auth.uid())
);

drop policy if exists prijave_nova on public.oglasnik_prijave;
create policy prijave_nova on public.oglasnik_prijave for insert
  with check (prijavitelj_id = auth.uid() and status = 'otvorena');
drop policy if exists prijave_admin on public.oglasnik_prijave;
create policy prijave_admin on public.oglasnik_prijave for select using (public.oglasnik_je_admin());
drop policy if exists prijave_rijesi on public.oglasnik_prijave;
create policy prijave_rijesi on public.oglasnik_prijave for update using (public.oglasnik_je_admin());

grant execute on function public.oglasnik_telefon(uuid) to authenticated;
grant execute on function public.oglasnik_procitano(uuid) to authenticated;
revoke execute on function public.oglasnik_telefon(uuid) from public, anon;
revoke execute on function public.oglasnik_procitano(uuid) from public, anon;

-- ---------- Slike ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('oglasnik-slike', 'oglasnik-slike', true, 3145728, array['image/webp', 'image/jpeg'])
on conflict (id) do nothing;

drop policy if exists oglasnik_slike_citaj on storage.objects;
create policy oglasnik_slike_citaj on storage.objects for select
  using (bucket_id = 'oglasnik-slike');
drop policy if exists oglasnik_slike_upload on storage.objects;
create policy oglasnik_slike_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'oglasnik-slike' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists oglasnik_slike_brisi on storage.objects;
create policy oglasnik_slike_brisi on storage.objects for delete to authenticated
  using (bucket_id = 'oglasnik-slike' and (storage.foldername(name))[1] = auth.uid()::text);

-- Okidačke funkcije ne trebaju biti dostupne kao RPC.
revoke execute on function public.oglasnik_profil_zastita() from public, anon, authenticated;
revoke execute on function public.oglasnik_oglas_zastita() from public, anon, authenticated;
revoke execute on function public.oglasnik_razgovor_novi() from public, anon, authenticated;
revoke execute on function public.oglasnik_poruka_nova() from public, anon, authenticated;
