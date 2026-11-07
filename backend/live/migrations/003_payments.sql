begin;
create table public.commerce_sellers (
 user_id uuid primary key references auth.users,
 stripe_account_id text unique not null,
 created_at timestamptz not null default now()
);
create table public.commerce_checkout_sessions (
 order_id uuid primary key references public.commerce_orders,
 session_id text unique,
 created_at timestamptz not null default now()
);
alter table public.commerce_sellers enable row level security;
alter table public.commerce_checkout_sessions enable row level security;
revoke all on public.commerce_sellers,public.commerce_checkout_sessions from anon,authenticated;
grant select on public.commerce_sellers to authenticated;
create policy seller_own on public.commerce_sellers for select to authenticated using(user_id=auth.uid());
grant all on public.commerce_sellers,public.commerce_checkout_sessions to service_role;
-- Server workers may read orders but never expose private destinations publicly.
grant select on public.commerce_orders,public.commerce_shipments to service_role;
-- Once checkout starts, a browser cannot cancel/restock underneath payment.
create function public.commerce_checkout_guard() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status='awaiting_payment' and exists(
   select 1 from commerce_checkout_sessions where order_id=old.id) then
   raise exception 'CHECKOUT_IN_PROGRESS';
 end if;
 return new;
end $$;
revoke all on function public.commerce_checkout_guard() from public,anon,authenticated;
create trigger checkout_guard before update on public.commerce_orders
 for each row execute function public.commerce_checkout_guard();
commit;
