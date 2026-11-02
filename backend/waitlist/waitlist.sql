-- Lista čekanja za marketinšku stranicu (site/index.html).
-- Već primijenjeno na Supabase projekt "loop" (migracije subhasto_waitlist*).
-- Tablica je zaključana (RLS bez politika); javnost koristi samo funkcije.

create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 254),
  role text not null default 'kupac' check (role in ('kupac','prodavac','oboje')),
  city text check (city is null or length(city) <= 80),
  code text not null unique default substr(replace(gen_random_uuid()::text,'-',''),1,8),
  referred_by text,
  referrals int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.waitlist enable row level security;

-- Mjesto na listi: svaka preporuka pomiče jedan dan naprijed.
create or replace function public.waitlist_rank(p_code text)
returns int language sql stable security definer set search_path = public as $$
  with me as (select created_at, referrals from waitlist where code = p_code)
  select (select count(*)::int + 1 from waitlist w, me
          where extract(epoch from w.created_at) - w.referrals * 86400
              < extract(epoch from me.created_at) - me.referrals * 86400)
$$;

create or replace function public.waitlist_join(p_email text, p_role text default 'kupac', p_city text default null, p_ref text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_code text; v_email text := lower(trim(p_email));
begin
  if exists (select 1 from waitlist where email = v_email) then
    return json_build_object('exists', true, 'total', (select count(*) from waitlist));
  end if;
  insert into waitlist(email, role, city, referred_by)
  values (v_email, coalesce(nullif(p_role,''),'kupac'), nullif(trim(p_city),''),
          case when exists(select 1 from waitlist where code = p_ref) then p_ref end)
  returning code into v_code;
  if p_ref is not null then
    update waitlist set referrals = referrals + 1 where code = p_ref and code <> v_code;
  end if;
  return json_build_object('code', v_code, 'position', waitlist_rank(v_code),
    'total', (select count(*) from waitlist), 'exists', false);
end $$;

create or replace function public.waitlist_status(p_code text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('position', waitlist_rank(code), 'referrals', referrals,
                           'total', (select count(*) from waitlist))
  from waitlist where code = p_code
$$;

create or replace function public.waitlist_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from waitlist
$$;

revoke all on function public.waitlist_rank(text) from public, anon, authenticated;
revoke all on function public.waitlist_join(text,text,text,text) from public;
revoke all on function public.waitlist_status(text) from public;
revoke all on function public.waitlist_count() from public;
grant execute on function public.waitlist_join(text,text,text,text) to anon, authenticated;
grant execute on function public.waitlist_status(text) to anon, authenticated;
grant execute on function public.waitlist_count() to anon, authenticated;
