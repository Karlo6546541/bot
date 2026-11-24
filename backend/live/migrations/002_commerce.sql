-- Apply after 001_live.sql. Authenticated social, inventory and fulfillment core.
begin;
create table public.commerce_products (
 id uuid primary key default gen_random_uuid(), seller_id uuid not null references auth.users,
 title text not null check(length(trim(title)) between 1 and 160),
 price_cents bigint not null check(price_cents between 1 and 100000000),
 stock integer not null check(stock between 0 and 100000), active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.commerce_orders (
 id uuid primary key default gen_random_uuid(), buyer_id uuid not null references auth.users,
 seller_id uuid not null references auth.users, product_id uuid references public.commerce_products,
 award_lot_id uuid unique references public.live_awards(lot_id),
 quantity integer not null check(quantity between 1 and 100),
 total_cents bigint not null check(total_cents>0), currency text not null default 'EUR' check(currency='EUR'),
 request_id uuid not null, status text not null default 'awaiting_payment'
 check(status in ('awaiting_payment','paid','shipped','delivered','cancelled','refunded')),
 created_at timestamptz not null default now(), unique(buyer_id,request_id), check(buyer_id<>seller_id)
);
create table public.commerce_payment_events (
 provider_event_id text primary key, order_id uuid not null references public.commerce_orders,
 event_type text not null, created_at timestamptz not null default now()
);
create table public.commerce_shipments (
 order_id uuid primary key references public.commerce_orders,
 method text not null check(method in ('boxnow','courier','pickup')),
 destination jsonb not null check(jsonb_typeof(destination)='object'),
 carrier text, tracking text, updated_at timestamptz not null default now()
);
create table public.commerce_follows (
 follower_id uuid not null references auth.users, seller_id uuid not null references auth.users,
 created_at timestamptz not null default now(), primary key(follower_id,seller_id),check(follower_id<>seller_id)
);
create table public.commerce_favorites (
 user_id uuid not null references auth.users, product_id uuid not null references public.commerce_products on delete cascade,
 primary key(user_id,product_id)
);
create table public.commerce_notifications (
 id bigint generated always as identity primary key, user_id uuid not null references auth.users,
 kind text not null, order_id uuid references public.commerce_orders,
 read_at timestamptz, created_at timestamptz not null default now()
);
create index on public.commerce_orders(buyer_id,created_at desc);
create index on public.commerce_orders(seller_id,created_at desc);
create index on public.commerce_notifications(user_id,id desc);
do $$ declare t text; begin
 foreach t in array array['commerce_products','commerce_orders','commerce_payment_events','commerce_shipments','commerce_follows','commerce_favorites','commerce_notifications'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
grant select on public.commerce_products to anon;
create policy products_read on public.commerce_products for select to anon,authenticated using(active or seller_id=auth.uid());
create policy orders_read on public.commerce_orders for select to authenticated using(auth.uid() in (buyer_id,seller_id));
create policy shipments_read on public.commerce_shipments for select to authenticated using(exists(select 1 from commerce_orders where id=order_id and auth.uid() in (buyer_id,seller_id)));
create policy follows_read on public.commerce_follows for select to authenticated using(auth.uid() in (follower_id,seller_id));
create policy favorites_read on public.commerce_favorites for select to authenticated using(user_id=auth.uid());
create policy notifications_read on public.commerce_notifications for select to authenticated using(user_id=auth.uid());
create function public.commerce_publish(p_title text,p_price bigint,p_stock integer) returns public.commerce_products
language plpgsql security definer set search_path=public as $$ declare p commerce_products; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 insert into commerce_products(seller_id,title,price_cents,stock) values(auth.uid(),trim(p_title),p_price,p_stock) returning * into p; return p;
end $$;
create function public.commerce_follow(p_seller uuid,p_follow boolean) returns void
language plpgsql security definer set search_path=public as $$ begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_follow then insert into commerce_follows values(auth.uid(),p_seller,now()) on conflict do nothing;
 else delete from commerce_follows where follower_id=auth.uid() and seller_id=p_seller; end if;
end $$;
create function public.commerce_favorite(p_product uuid,p_favorite boolean) returns void
language plpgsql security definer set search_path=public as $$ begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_favorite then insert into commerce_favorites values(auth.uid(),p_product) on conflict do nothing;
 else delete from commerce_favorites where user_id=auth.uid() and product_id=p_product; end if;
end $$;
create function public.commerce_reserve(p_product uuid,p_quantity integer,p_request uuid) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare p commerce_products; o commerce_orders; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into o from commerce_orders where buyer_id=auth.uid() and request_id=p_request;
 if found then
 if o.product_id is distinct from p_product or o.quantity<>p_quantity then raise exception 'REQUEST_CONFLICT'; end if; return o; end if;
 if p_quantity not between 1 and 100 or p_quantity is null then raise exception 'INVALID_QUANTITY'; end if;
 select * into p from commerce_products where id=p_product for update;
 if not found or not p.active or p.stock<p_quantity or p.seller_id=auth.uid() then raise exception 'UNAVAILABLE'; end if;
 update commerce_products set stock=stock-p_quantity where id=p_product;
 insert into commerce_orders(buyer_id,seller_id,product_id,quantity,total_cents,request_id)
 values(auth.uid(),p.seller_id,p.id,p_quantity,p.price_cents*p_quantity,p_request) returning * into o;
 return o;
end $$;
create function public.commerce_claim_award(p_lot uuid,p_request uuid) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare a live_awards; o commerce_orders; sid uuid; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into a from live_awards where lot_id=p_lot for update;
 if not found or a.buyer_id<>auth.uid() or a.status<>'awaiting_checkout' then raise exception 'AWARD_UNAVAILABLE'; end if;
 select * into o from commerce_orders where award_lot_id=p_lot;
 if found then return o; end if;
 select r.host_id into sid from live_lots l join live_rooms r on r.id=l.room_id where l.id=p_lot;
 insert into commerce_orders(buyer_id,seller_id,award_lot_id,quantity,total_cents,request_id)
 values(auth.uid(),sid,p_lot,1,a.amount_cents,p_request) returning * into o; return o;
end $$;
create function public.commerce_choose_shipping(p_order uuid,p_method text,p_destination jsonb) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.buyer_id<>auth.uid() or auth.uid() is null then raise exception 'BUYER_ONLY'; end if;
 if o.status not in ('awaiting_payment','paid') then raise exception 'ORDER_LOCKED'; end if;
 if p_method='boxnow' and coalesce(length(p_destination->>'locker_id'),0)=0 then raise exception 'LOCKER_REQUIRED'; end if;
 if p_method='courier' and coalesce(length(p_destination->>'address'),0)=0 then raise exception 'ADDRESS_REQUIRED'; end if;
 insert into commerce_shipments(order_id,method,destination) values(p_order,p_method,p_destination)
 on conflict(order_id) do update set method=excluded.method,destination=excluded.destination,updated_at=now();
end $$;
-- Only a trusted webhook worker may call this, AFTER checking provider signature,
-- payment amount, currency and order ID. Browser cannot mark its own orders paid.
create function public.commerce_record_payment(p_event text,p_order uuid,p_amount bigint,p_currency text) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.total_cents<>p_amount or o.currency<>p_currency then raise exception 'PAYMENT_MISMATCH'; end if;
 if exists(select 1 from commerce_payment_events where provider_event_id=p_event) then
 if not exists(select 1 from commerce_payment_events where provider_event_id=p_event and order_id=p_order) then raise exception 'EVENT_CONFLICT'; end if; return; end if;
 if o.status<>'awaiting_payment' then raise exception 'INVALID_PAYMENT_STATE'; end if;
 insert into commerce_payment_events values(p_event,p_order,'paid',now());
 update commerce_orders set status='paid' where id=p_order;
 update live_awards set status='paid' where lot_id=o.award_lot_id;
 insert into commerce_notifications(user_id,kind,order_id) values(o.buyer_id,'order_paid',o.id),(o.seller_id,'order_to_ship',o.id);
end $$;
create function public.commerce_cancel(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or auth.uid() is null or auth.uid() not in (o.buyer_id,o.seller_id) then raise exception 'ACCESS_DENIED'; end if;
 if o.status='cancelled' then return; end if;
 if o.status<>'awaiting_payment' then raise exception 'REFUND_REQUIRED'; end if;
 update commerce_orders set status='cancelled' where id=p_order;
 update commerce_products set stock=stock+o.quantity where id=o.product_id;
 update live_awards set status='cancelled' where lot_id=o.award_lot_id;
end $$;
create function public.commerce_ship(p_order uuid,p_carrier text,p_tracking text) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or auth.uid() is null or o.seller_id<>auth.uid() then raise exception 'SELLER_ONLY'; end if;
 if o.status<>'paid' then raise exception 'PAYMENT_REQUIRED'; end if;
 if coalesce(length(trim(p_tracking)),0)=0 then raise exception 'TRACKING_REQUIRED'; end if;
 update commerce_shipments set carrier=p_carrier,tracking=p_tracking,updated_at=now() where order_id=p_order;
 if not found then raise exception 'SHIPPING_REQUIRED'; end if;
 update commerce_orders set status='shipped' where id=p_order;
 insert into commerce_notifications(user_id,kind,order_id) values(o.buyer_id,'order_shipped',o.id);
end $$;
create function public.commerce_confirm_delivery(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ begin
 update commerce_orders set status='delivered' where id=p_order and buyer_id=auth.uid() and status='shipped';
 if not found then raise exception 'INVALID_DELIVERY'; end if;
end $$;
create function public.commerce_read_notification(p_id bigint) returns void
language plpgsql security definer set search_path=public as $$ begin
 update commerce_notifications set read_at=now() where id=p_id and user_id=auth.uid();
end $$;
do $$ declare f record; begin
 for f in select oid::regprocedure as sig from pg_proc where pronamespace='public'::regnamespace and proname like 'commerce\_%' escape '\' loop
 execute format('revoke all on function %s from public,anon',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
revoke execute on function public.commerce_record_payment(text,uuid,bigint,text) from authenticated;
-- Supabase service_role is used by verified webhook workers only.
grant execute on function public.commerce_record_payment(text,uuid,bigint,text) to service_role;
commit;
