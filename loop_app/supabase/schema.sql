-- =============================================================================
-- LOOP — online baza za TESTIRANJE (Supabase / Postgres)
--
-- Kako koristiti: Supabase → SQL Editor → New query → zalijepi cijelu
-- datoteku → Run. Skripta se smije pokrenuti više puta (i preko starije
-- verzije — postojeći podaci ostaju).
--
-- Model: aplikacija sprema dokumente (JSON) u tablice `loop_*`, isto kao
-- lokalno (Hive). Svaka tablica ima `id`, `data` (jsonb) i `updated_at`.
-- Realtime je uključen pa svi testeri odmah vide promjene drugih.
--
-- Pristup:
--   • čitati smiju svi (i gost koji samo razgledava),
--   • pisati smiju samo PRIJAVLJENI korisnici (Supabase Auth),
--   • korisničko ime je jedinstveno (tablica loop_usernames),
--   • korisnik može obrisati samo SVOJ račun za prijavu.
--
-- ⚠️ I dalje TESTNA verzija: pravila trgovanja (krediti, ponude) provjerava
-- aplikacija, ne server — prijavljeni korisnik bi teoretski mogao ručno
-- mijenjati tuđe zapise. Za pravi novac/korisnike to ide u funkcije na
-- serveru (vidi README, "Put do produkcije").
-- =============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'loop_users', 'loop_devices', 'loop_transactions',
    'loop_history', 'loop_auctions', 'loop_deliveries',
    'loop_reviews', 'loop_notifications', 'loop_reports',
    'loop_messages', 'loop_offers'
  ]
  loop
    execute format(
      'create table if not exists public.%I (
         id text primary key,
         data jsonb not null,
         updated_at timestamptz not null default now()
       )', t);
    execute format(
      'create index if not exists %I on public.%I (updated_at desc)',
      t || '_updated_idx', t);

    execute format('alter table public.%I enable row level security', t);
    -- Stara pravila (sve za sve) se uklanjaju.
    execute format('drop policy if exists "test_all_access" on public.%I', t);
    execute format('drop policy if exists "loop_read" on public.%I', t);
    execute format('drop policy if exists "loop_write" on public.%I', t);
    execute format(
      'create policy "loop_read" on public.%I
         for select to anon, authenticated using (true)', t);
    execute format(
      'create policy "loop_write" on public.%I
         for all to authenticated using (true) with check (true)', t);

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = t
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Jedinstvena korisnička imena. Ime je primarni ključ (mala slova), pa ni
-- dva istovremena zahtjeva ne mogu dobiti isto ime. Brisanjem računa za
-- prijavu ime se automatski oslobađa (on delete cascade).
-- -----------------------------------------------------------------------------
create table if not exists public.loop_usernames (
  username text primary key
    check (username = lower(username) and username ~ '^[a-z][a-z0-9_.]{2,19}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.loop_usernames enable row level security;
drop policy if exists "usernames_read" on public.loop_usernames;
create policy "usernames_read" on public.loop_usernames
  for select to anon, authenticated using (true);
drop policy if exists "usernames_claim" on public.loop_usernames;
create policy "usernames_claim" on public.loop_usernames
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "usernames_release" on public.loop_usernames;
create policy "usernames_release" on public.loop_usernames
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Brisanje računa
-- -----------------------------------------------------------------------------
-- "Obriši odmah": prijavljeni korisnik briše SVOJ račun za prijavu.
create or replace function public.loop_delete_me()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Nisi prijavljen.';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.loop_delete_me() from public, anon;
grant execute on function public.loop_delete_me() to authenticated;

-- Računi zakazani za brisanje prije više od 7 dana (profil ima
-- deletionRequestedAt). Aplikacija je poziva pri pokretanju, prije nego
-- što obriše same profile.
create or replace function public.loop_purge_deleted()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  delete from auth.users u
  using public.loop_users p
  where p.id = u.id::text
    and p.data ? 'deletionRequestedAt'
    and jsonb_typeof(p.data -> 'deletionRequestedAt') = 'string'
    and (p.data ->> 'deletionRequestedAt')::timestamptz
        < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.loop_purge_deleted() from public;
grant execute on function public.loop_purge_deleted() to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Pregled: koliko je zapisa u kojoj tablici.
-- -----------------------------------------------------------------------------
create or replace view public.loop_stats
  with (security_invoker = true) as
  select 'users' as tablica, count(*) from public.loop_users
  union all select 'devices', count(*) from public.loop_devices
  union all select 'transactions', count(*) from public.loop_transactions
  union all select 'auctions', count(*) from public.loop_auctions
  union all select 'deliveries', count(*) from public.loop_deliveries
  union all select 'history', count(*) from public.loop_history
  union all select 'reviews', count(*) from public.loop_reviews
  union all select 'notifications', count(*) from public.loop_notifications
  union all select 'reports', count(*) from public.loop_reports
  union all select 'messages', count(*) from public.loop_messages
  union all select 'offers', count(*) from public.loop_offers
  union all select 'usernames', count(*) from public.loop_usernames;

-- Brisanje svih testnih podataka (pokreni ručno kad treba):
-- truncate public.loop_users, public.loop_devices, public.loop_transactions,
--          public.loop_history, public.loop_auctions, public.loop_deliveries,
--          public.loop_reviews, public.loop_notifications, public.loop_reports,
--          public.loop_messages, public.loop_offers;

-- -----------------------------------------------------------------------------
-- Fotografije (predmeti i profilne slike) — Supabase Storage.
-- Čitati smiju svi, dodavati i brisati samo prijavljeni.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'loop-images', 'loop-images', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "loop_images_test_read" on storage.objects;
create policy "loop_images_test_read" on storage.objects
  for select to anon, authenticated using (bucket_id = 'loop-images');

drop policy if exists "loop_images_test_insert" on storage.objects;
create policy "loop_images_test_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'loop-images');

drop policy if exists "loop_images_test_delete" on storage.objects;
create policy "loop_images_test_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'loop-images');
