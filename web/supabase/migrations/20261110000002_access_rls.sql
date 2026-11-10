-- =============================================================================
-- Access helpers + Row Level Security
-- The SQL access rule mirrors src/lib/access/canReadChapter.ts — keep in sync.
-- =============================================================================

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_approved_creator()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.creators where id = auth.uid() and status = 'approved');
$$;

create or replace function public.owns_series(p_series uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.series where id = p_series and creator_id = auth.uid());
$$;

create or replace function public.owns_chapter(p_chapter uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.chapters c join public.series s on s.id = c.series_id
    where c.id = p_chapter and s.creator_id = auth.uid()
  );
$$;

-- Storage paths are "<series_id>/..." — safe text -> uuid ownership check.
create or replace function public.owns_series_path(p_folder text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if p_folder is null or p_folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1 from public.series s
    join public.creators c on c.id = s.creator_id and c.status = 'approved'
    where s.id = p_folder::uuid and s.creator_id = auth.uid()
  );
end $$;

create or replace function public.series_is_public(p_series uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.series where id = p_series and status = 'published' and not hidden_by_admin
  );
$$;

create or replace function public.has_active_subscription(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.subscriptions
    where user_id = p_user and status = 'active' and current_period_end > now()
  );
$$;

-- Core rule. NOT exposed to clients (takes an arbitrary user id).
create or replace function public.can_user_read_chapter(p_chapter uuid, p_user uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  r record;
  v_role public.user_role;
begin
  select c.id, c.number, c.access, c.early_access_until, c.published, c.publish_at,
         s.creator_id, s.status, s.hidden_by_admin, s.free_chapters
    into r
    from public.chapters c join public.series s on s.id = c.series_id
   where c.id = p_chapter;
  if not found then return false; end if;

  if p_user is not null then
    select role into v_role from public.profiles where id = p_user;
    if v_role = 'admin' or r.creator_id = p_user then return true; end if;
  end if;

  if r.status <> 'published' or r.hidden_by_admin then return false; end if;
  if not r.published or r.publish_at > now() then return false; end if;

  if r.access = 'free'
     or (r.access = 'locked' and r.number <= r.free_chapters)
     or (r.access = 'early_access' and r.early_access_until <= now()) then
    return true;
  end if;

  if p_user is null then return false; end if;
  if public.has_active_subscription(p_user) then return true; end if;
  return exists (select 1 from public.chapter_unlocks where user_id = p_user and chapter_id = p_chapter);
end $$;

-- Client-safe wrapper: always evaluates for the caller.
create or replace function public.can_read_chapter(p_chapter uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.can_user_read_chapter(p_chapter, auth.uid());
$$;

revoke execute on function public.can_user_read_chapter(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.has_active_subscription(uuid) from public, anon, authenticated;
grant execute on function public.can_user_read_chapter(uuid, uuid) to service_role;
grant execute on function public.has_active_subscription(uuid) to service_role;

-- =============================================================================
-- RLS
-- =============================================================================
alter table public.profiles                 enable row level security;
alter table public.billing_customers        enable row level security;
alter table public.creators                 enable row level security;
alter table public.series                   enable row level security;
alter table public.chapters                 enable row level security;
alter table public.chapter_pages            enable row level security;
alter table public.follows                  enable row level security;
alter table public.reading_progress         enable row level security;
alter table public.pricing_plans            enable row level security;
alter table public.platform_settings        enable row level security;
alter table public.subscriptions            enable row level security;
alter table public.coin_balances            enable row level security;
alter table public.coin_transactions        enable row level security;
alter table public.chapter_unlocks          enable row level security;
alter table public.payments                 enable row level security;
alter table public.chapter_reads            enable row level security;
alter table public.creator_earnings         enable row level security;
alter table public.processed_payment_events enable row level security;

-- Defense in depth: clients never write money / config / audit tables, even if
-- a policy were added by mistake. Writes go through the server (service role).
revoke insert, update, delete, truncate on
  public.billing_customers, public.pricing_plans, public.platform_settings,
  public.subscriptions, public.coin_balances, public.coin_transactions,
  public.chapter_unlocks, public.payments, public.chapter_reads,
  public.creator_earnings, public.processed_payment_events
from anon, authenticated;

-- Column-level write grants for user-editable tables.
revoke insert, update on public.profiles, public.creators, public.series from anon, authenticated;
grant update (username, display_name, avatar_url, locale) on public.profiles to authenticated;
grant insert (id, pen_name, bio, portfolio_url, application_note) on public.creators to authenticated;
grant update (pen_name, bio, portfolio_url) on public.creators to authenticated;
grant insert (creator_id, slug, title, description, cover_path, genres, status, free_chapters)
  on public.series to authenticated;
grant update (slug, title, description, cover_path, genres, status, free_chapters)
  on public.series to authenticated;

-- profiles
create policy profiles_select on public.profiles for select using (true);
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- creators
create policy creators_select on public.creators for select
  using (status = 'approved' or id = auth.uid() or public.is_admin());
create policy creators_apply on public.creators for insert to authenticated
  with check (id = auth.uid());
create policy creators_update_own on public.creators for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- series
create policy series_select on public.series for select
  using ((status = 'published' and not hidden_by_admin) or creator_id = auth.uid() or public.is_admin());
create policy series_insert on public.series for insert to authenticated
  with check (creator_id = auth.uid() and public.is_approved_creator());
create policy series_update on public.series for update to authenticated
  using (creator_id = auth.uid() and public.is_approved_creator())
  with check (creator_id = auth.uid());
create policy series_delete on public.series for delete to authenticated
  using (creator_id = auth.uid() and status = 'draft');

-- chapters (metadata is visible once released; page images are guarded separately)
create policy chapters_select on public.chapters for select
  using (
    (published and publish_at <= now() and public.series_is_public(series_id))
    or public.owns_series(series_id) or public.is_admin()
  );
create policy chapters_insert on public.chapters for insert to authenticated
  with check (public.owns_series(series_id) and public.is_approved_creator());
create policy chapters_update on public.chapters for update to authenticated
  using (public.owns_series(series_id) and public.is_approved_creator())
  with check (public.owns_series(series_id));
create policy chapters_delete on public.chapters for delete to authenticated
  using (public.owns_series(series_id));

-- chapter_pages: the access rule itself
create policy chapter_pages_select on public.chapter_pages for select
  using (public.can_read_chapter(chapter_id));
create policy chapter_pages_insert on public.chapter_pages for insert to authenticated
  with check (public.owns_chapter(chapter_id) and public.is_approved_creator());
create policy chapter_pages_update on public.chapter_pages for update to authenticated
  using (public.owns_chapter(chapter_id)) with check (public.owns_chapter(chapter_id));
create policy chapter_pages_delete on public.chapter_pages for delete to authenticated
  using (public.owns_chapter(chapter_id));

-- follows
create policy follows_select on public.follows for select to authenticated using (user_id = auth.uid());
create policy follows_insert on public.follows for insert to authenticated
  with check (user_id = auth.uid() and public.series_is_public(series_id));
create policy follows_delete on public.follows for delete to authenticated using (user_id = auth.uid());

-- reading_progress
create policy progress_select on public.reading_progress for select to authenticated
  using (user_id = auth.uid());
create policy progress_insert on public.reading_progress for insert to authenticated
  with check (user_id = auth.uid());
create policy progress_update on public.reading_progress for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy progress_delete on public.reading_progress for delete to authenticated
  using (user_id = auth.uid());

-- config (read-only to clients)
create policy plans_select on public.pricing_plans for select using (active or public.is_admin());
create policy settings_select on public.platform_settings for select using (true);

-- own money rows (read-only)
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy balances_select on public.coin_balances for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy coin_tx_select on public.coin_transactions for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy unlocks_select on public.chapter_unlocks for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy payments_select on public.payments for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy earnings_select on public.creator_earnings for select to authenticated
  using (creator_id = auth.uid() or public.is_admin());
create policy reads_select_admin on public.chapter_reads for select to authenticated
  using (public.is_admin());
create policy events_select_admin on public.processed_payment_events for select to authenticated
  using (public.is_admin());
-- billing_customers: no policies => no client access at all.
