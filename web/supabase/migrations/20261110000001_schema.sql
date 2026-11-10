-- =============================================================================
-- Kadar — core schema
-- =============================================================================
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------- enums ----------
create type public.user_role as enum ('reader', 'creator', 'admin');
create type public.creator_status as enum ('pending', 'approved', 'rejected');
create type public.series_status as enum ('draft', 'published');
create type public.chapter_access as enum ('free', 'locked', 'early_access');
create type public.subscription_status as enum ('active', 'canceled', 'expired', 'past_due');
create type public.coin_tx_type as enum ('purchase', 'unlock', 'admin_grant', 'refund');
create type public.payment_provider as enum ('mock', 'stripe');
create type public.earning_source as enum ('coin_unlock', 'subscription_pool');
create type public.plan_kind as enum ('subscription', 'coin_pack');

-- ---------- updated_at helper ----------
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------- users ----------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text unique check (username ~ '^[a-z0-9_]{3,30}$'),
  display_name text not null default '' check (char_length(display_name) <= 60),
  avatar_url   text,
  role         public.user_role not null default 'reader',
  locale       text not null default 'hr',
  created_at   timestamptz not null default now()
);

-- Provider customer ids (e.g. Stripe customer). Server-only.
create table public.billing_customers (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  provider    public.payment_provider not null,
  customer_id text not null unique,
  created_at  timestamptz not null default now(),
  primary key (user_id, provider)
);

create table public.creators (
  id                uuid primary key references public.profiles (id) on delete cascade,
  status            public.creator_status not null default 'pending',
  pen_name          text not null check (char_length(pen_name) between 2 and 60),
  bio               text not null default '' check (char_length(bio) <= 2000),
  portfolio_url     text,
  application_note  text not null default '' check (char_length(application_note) <= 2000),
  -- null = use platform default (platform_settings.creator_share_pct)
  revenue_share_pct numeric(5, 2) check (revenue_share_pct between 0 and 100),
  reviewed_by       uuid references public.profiles (id),
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now()
);

-- ---------- content ----------
create table public.series (
  id              uuid primary key default gen_random_uuid(),
  creator_id      uuid not null references public.creators (id) on delete cascade,
  slug            text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title           text not null check (char_length(title) between 1 and 120),
  description     text not null default '' check (char_length(description) <= 4000),
  cover_path      text,
  genres          text[] not null default '{}',
  status          public.series_status not null default 'draft',
  hidden_by_admin boolean not null default false,
  moderation_note text,
  free_chapters   int not null default 3 check (free_chapters between 0 and 1000),
  search_text     text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index series_creator_idx on public.series (creator_id);
create index series_public_idx on public.series (status, hidden_by_admin, updated_at desc);
create index series_genres_idx on public.series using gin (genres);
create index series_search_idx on public.series using gin (search_text extensions.gin_trgm_ops);

create table public.chapters (
  id                 uuid primary key default gen_random_uuid(),
  series_id          uuid not null references public.series (id) on delete cascade,
  number             int not null check (number > 0),
  title              text not null default '' check (char_length(title) <= 120),
  access             public.chapter_access not null default 'locked',
  coin_price         int not null default 5 check (coin_price between 0 and 10000),
  early_access_until timestamptz,
  -- false = draft. true = released at publish_at (may be in the future = scheduled)
  published          boolean not null default false,
  publish_at         timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (series_id, number),
  check (access <> 'early_access' or early_access_until is not null)
);
create index chapters_series_idx on public.chapters (series_id, number);

create table public.chapter_pages (
  id           uuid primary key default gen_random_uuid(),
  chapter_id   uuid not null references public.chapters (id) on delete cascade,
  position     int not null check (position >= 0),
  storage_path text not null unique,
  width        int not null check (width > 0),
  height       int not null check (height > 0),
  created_at   timestamptz not null default now(),
  unique (chapter_id, position) deferrable initially deferred
);

-- ---------- reader state ----------
create table public.follows (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  series_id  uuid not null references public.series (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, series_id)
);
create index follows_series_idx on public.follows (series_id);

create table public.reading_progress (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  chapter_id   uuid not null references public.chapters (id) on delete cascade,
  series_id    uuid not null references public.series (id) on delete cascade,
  page_index   int not null default 0 check (page_index >= 0),
  scroll_ratio real not null default 0 check (scroll_ratio between 0 and 1),
  completed    boolean not null default false,
  updated_at   timestamptz not null default now(),
  primary key (user_id, chapter_id)
);
create index reading_progress_recent_idx on public.reading_progress (user_id, updated_at desc);

-- ---------- monetization config ----------
create table public.pricing_plans (
  id              uuid primary key default gen_random_uuid(),
  kind            public.plan_kind not null,
  code            text not null unique,
  name            text not null,
  price_cents     int not null check (price_cents > 0),
  currency        text not null default 'EUR',
  coins           int check (coins > 0),
  stripe_price_id text,
  active          boolean not null default true,
  sort            int not null default 0,
  check ((kind = 'coin_pack') = (coins is not null))
);

create table public.platform_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------- money ----------
create table public.subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references public.profiles (id) on delete cascade,
  plan_id                  uuid references public.pricing_plans (id),
  provider                 public.payment_provider not null,
  provider_subscription_id text not null unique,
  provider_customer_id     text,
  status                   public.subscription_status not null,
  current_period_start     timestamptz not null,
  current_period_end       timestamptz not null,
  cancel_at_period_end     boolean not null default false,
  canceled_at              timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index subscriptions_user_idx on public.subscriptions (user_id, status, current_period_end desc);

create table public.coin_balances (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  balance    int not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table public.coin_transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  type          public.coin_tx_type not null,
  amount        int not null check (amount <> 0), -- + credit, - debit
  balance_after int not null,
  chapter_id    uuid references public.chapters (id) on delete set null,
  plan_id       uuid references public.pricing_plans (id),
  provider      public.payment_provider,
  provider_ref  text,
  note          text,
  created_at    timestamptz not null default now()
);
create index coin_transactions_user_idx on public.coin_transactions (user_id, created_at desc);
create unique index coin_transactions_ref_uidx on public.coin_transactions (type, provider_ref)
  where provider_ref is not null;

create table public.chapter_unlocks (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  chapter_id  uuid not null references public.chapters (id) on delete cascade,
  coins_spent int not null check (coins_spent >= 0),
  created_at  timestamptz not null default now(),
  primary key (user_id, chapter_id)
);

-- Money actually received (one row per successful charge).
create table public.payments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  kind         public.plan_kind not null,
  plan_id      uuid references public.pricing_plans (id),
  provider     public.payment_provider not null,
  provider_ref text not null unique,
  amount_cents int not null check (amount_cents >= 0),
  currency     text not null default 'EUR',
  period       date not null, -- first day of month
  created_at   timestamptz not null default now()
);
create index payments_period_idx on public.payments (period, kind);

-- Reads used to split the subscription pool between creators.
create table public.chapter_reads (
  user_id       uuid not null references public.profiles (id) on delete cascade,
  chapter_id    uuid not null references public.chapters (id) on delete cascade,
  series_id     uuid not null references public.series (id) on delete cascade,
  creator_id    uuid not null references public.creators (id) on delete cascade,
  access_reason text not null,
  period        date not null,
  created_at    timestamptz not null default now(),
  primary key (user_id, chapter_id, period)
);
create index chapter_reads_period_idx on public.chapter_reads (period, access_reason);

create table public.creator_earnings (
  id             uuid primary key default gen_random_uuid(),
  creator_id     uuid not null references public.creators (id) on delete cascade,
  series_id      uuid references public.series (id) on delete set null,
  chapter_id     uuid references public.chapters (id) on delete set null,
  source         public.earning_source not null,
  gross_cents    int not null check (gross_cents >= 0),
  creator_cents  int not null check (creator_cents >= 0),
  platform_cents int not null check (platform_cents >= 0),
  share_pct      numeric(5, 2) not null,
  period         date not null,
  ref            text not null,
  created_at     timestamptz not null default now(),
  unique (source, ref, creator_id)
);
create index creator_earnings_creator_idx on public.creator_earnings (creator_id, period);

create table public.processed_payment_events (
  provider     text not null,
  event_id     text not null,
  type         text not null,
  processed_at timestamptz not null default now(),
  primary key (provider, event_id)
);

-- ---------- triggers ----------
create trigger series_touch before update on public.series
  for each row execute function public.touch_updated_at();
create trigger chapters_touch before update on public.chapters
  for each row execute function public.touch_updated_at();
create trigger subscriptions_touch before update on public.subscriptions
  for each row execute function public.touch_updated_at();

-- Normalised search text (lowercase, no diacritics: "čudo" -> "cudo").
create or replace function public.series_search_text()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.search_text := lower(extensions.unaccent(
    coalesce(new.title, '') || ' ' ||
    array_to_string(new.genres, ' ') || ' ' ||
    coalesce((select c.pen_name from public.creators c where c.id = new.creator_id), '')
  ));
  return new;
end $$;
create trigger series_search before insert or update of title, genres, creator_id on public.series
  for each row execute function public.series_search_text();

-- Keep search text in sync when a creator renames themselves.
create or replace function public.creator_pen_name_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.series set title = title where creator_id = new.id;
  return new;
end $$;
create trigger creators_pen_name after update of pen_name on public.creators
  for each row execute function public.creator_pen_name_changed();

-- New auth user -> profile + empty coin balance.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1))
  );
  insert into public.coin_balances (user_id, balance) values (new.id, 0);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
