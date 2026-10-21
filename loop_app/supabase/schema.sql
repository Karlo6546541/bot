-- =============================================================================
-- LOOP — online baza za TESTIRANJE (Supabase / Postgres)
--
-- Kako koristiti: Supabase → SQL Editor → New query → zalijepi cijelu
-- datoteku → Run. Skripta se smije pokrenuti više puta.
--
-- Model: aplikacija sprema dokumente (JSON) u šest tablica, isto kao lokalno
-- (Hive). Svaka tablica ima `id`, `data` (jsonb) i `updated_at`.
-- Realtime je uključen pa svi testeri odmah vide promjene drugih.
--
-- ⚠️ SAMO ZA TEST: pravila ispod dopuštaju svakome s javnim ključem čitanje
-- i pisanje svih podataka. Ne koristiti s pravim korisnicima ni novcem.
-- Za produkciju vidi README ("Put do produkcije").
-- =============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'loop_users', 'loop_devices', 'loop_transactions',
    'loop_history', 'loop_auctions', 'loop_deliveries'
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

    -- Row Level Security: uključen, ali (za test) otvoren za sve.
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "test_all_access" on public.%I', t);
    execute format(
      'create policy "test_all_access" on public.%I
         for all to anon, authenticated
         using (true) with check (true)', t);

    -- Realtime (promjene u stvarnom vremenu).
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

-- Pregled: koliko je zapisa u kojoj tablici.
create or replace view public.loop_stats
  with (security_invoker = true) as
  select 'users' as tablica, count(*) from public.loop_users
  union all select 'devices', count(*) from public.loop_devices
  union all select 'transactions', count(*) from public.loop_transactions
  union all select 'auctions', count(*) from public.loop_auctions
  union all select 'deliveries', count(*) from public.loop_deliveries
  union all select 'history', count(*) from public.loop_history;

-- Brisanje svih testnih podataka (pokreni ručno kad treba):
-- truncate public.loop_users, public.loop_devices, public.loop_transactions,
--          public.loop_history, public.loop_auctions, public.loop_deliveries;
