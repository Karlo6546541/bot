begin;
alter table public.commerce_orders add column source_device text;
alter table public.commerce_orders add column source_snapshot jsonb;
-- Shipping is currently a free demo; keep its amount separate from item fees.
alter table public.commerce_orders add column shipping_cents bigint not null default 0 check(shipping_cents>=0 and shipping_cents<total_cents);
create index orders_source_device on public.commerce_orders(source_device) where status='awaiting_payment';

-- Bring existing Subhasto listings into the same authoritative payment flow.
create function public.commerce_reserve_device(p_device text,p_request uuid) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare d jsonb; o commerce_orders; cents bigint; available integer; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into o from commerce_orders where buyer_id=auth.uid() and request_id=p_request;
 if found then
  if o.source_device is distinct from p_device then raise exception 'REQUEST_CONFLICT'; end if; return o;
 end if;
 select data into d from loop_devices where id=p_device for update;
 if not found or d->>'ownerId' is null or d->>'ownerId'=auth.uid()::text or d->>'listPrice' is null then raise exception 'UNAVAILABLE'; end if;
 -- An interrupted purchase reopens the same order, rather than charging twice.
 select * into o from commerce_orders where buyer_id=auth.uid() and source_device=p_device and status='awaiting_payment' order by created_at desc limit 1;
 if found then return o; end if;
 available:=coalesce((d->>'quantity')::integer,1);
 if d->>'file' is null and (select count(*) from commerce_orders where source_device=p_device and status='awaiting_payment')>=available then raise exception 'UNAVAILABLE'; end if;
 cents:=round((d->>'listPrice')::numeric*100);
 if coalesce((d->>'discountPercent')::integer,0)>0 and (d->>'discountUntil' is null or (d->>'discountUntil')::timestamptz>now()) then cents:=round(cents*(100-(d->>'discountPercent')::integer)/100.0); end if;
 if cents<50 or cents>10000000 then raise exception 'INVALID_AMOUNT'; end if;
 insert into commerce_orders(buyer_id,seller_id,quantity,total_cents,request_id,source_device,source_snapshot)
 values(auth.uid(),(d->>'ownerId')::uuid,1,cents,p_request,p_device,d) returning * into o;
 -- Digital goods have no carrier cost; pickup is an internal zero-cost method.
 if d->>'file' is not null then insert into commerce_shipments(order_id,method,destination) values(o.id,'pickup','{}'); end if;
 return o;
end $$;
revoke all on function public.commerce_reserve_device(text,uuid) from public,anon;
grant execute on function public.commerce_reserve_device(text,uuid) to authenticated;

-- Existing permissive sync policy is narrowed for listing ownership.
create policy stripe_listing_insert on public.loop_devices as restrictive for insert to authenticated with check(data->>'ownerId'=auth.uid()::text);
create policy stripe_listing_update on public.loop_devices as restrictive for update to authenticated using(data->>'ownerId'=auth.uid()::text) with check(data->>'ownerId'=auth.uid()::text);
create policy stripe_listing_delete on public.loop_devices as restrictive for delete to authenticated using(data->>'ownerId'=auth.uid()::text);

create function public.commerce_freeze_listing() returns trigger language plpgsql set search_path=public as $$ begin
 if current_user not in ('postgres','service_role','supabase_admin') and exists(select 1 from commerce_orders where source_device=old.id and status='awaiting_payment') then raise exception 'ORDER_IN_PROGRESS'; end if;
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
create trigger stripe_listing_reserved before update or delete on public.loop_devices for each row execute function public.commerce_freeze_listing();

create function public.commerce_fulfill_device(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; d jsonb; bought text; tx jsonb; begin
 select * into o from commerce_orders where id=p_order for update;
 if o.source_device is null then return; end if;
 if exists(select 1 from loop_transactions where id='stripe-buy-'||o.id) then return; end if;
 select data into d from loop_devices where id=o.source_device for update;
 if d is null or d->>'ownerId' is distinct from o.seller_id::text then raise exception 'LISTING_CHANGED'; end if;
 bought:=o.source_device;
 if d->>'file' is null then
  if coalesce((d->>'quantity')::integer,1)>1 then
   bought:='stripe-item-'||o.id;
   insert into loop_devices(id,data) values(bought,d||jsonb_build_object('id',bought,'ownerId',o.buyer_id,'listPrice',null,'listedAt',null,'quantity',1,'discountPercent',0,'discountUntil',null));
   update loop_devices set data=d||jsonb_build_object('quantity',(d->>'quantity')::integer-1) where id=o.source_device;
  else update loop_devices set data=d||jsonb_build_object('ownerId',o.buyer_id,'listPrice',null,'listedAt',null,'quantity',1,'discountPercent',0,'discountUntil',null) where id=o.source_device;
  end if;
 end if;
 tx:=jsonb_build_object('deviceId',bought,'deviceName',coalesce(d->>'name','')||' '||coalesce(d->>'model',''),'price',(o.total_cents-o.shipping_cents)/100.0,'fee',0,'amount',o.total_cents/100.0,'buyerId',o.buyer_id,'sellerId',o.seller_id,'buyerLabel','','sellerLabel','','createdAt',now(),'isAuction',false);
 insert into loop_transactions(id,data) values('stripe-buy-'||o.id,tx||jsonb_build_object('id','stripe-buy-'||o.id,'type','buy','userId',o.buyer_id));
 insert into loop_transactions(id,data) values('stripe-sale-'||o.id,tx||jsonb_build_object('id','stripe-sale-'||o.id,'type','sell','userId',o.seller_id,'fee',((o.total_cents-o.shipping_cents)*6+50)/100/100.0,'amount',(o.total_cents-o.shipping_cents-((o.total_cents-o.shipping_cents)*6+50)/100)/100.0));
end $$;

-- Test-only platform balance: revenue is distinct from money owed to sellers.
create table public.commerce_customers (
 user_id uuid primary key references auth.users,
 customer_id text not null unique,
 consent_at timestamptz,
 consent_version text,
 created_at timestamptz not null default now()
);
create table public.commerce_payments (
 order_id uuid primary key references public.commerce_orders,
 intent_id text unique,
 attempt integer not null default 1 check(attempt>0),
 status text not null default 'pending' check(status in ('pending','paid','failed','refunded')),
 item_cents bigint not null check(item_cents>0),
 fee_cents bigint not null check(fee_cents>=0 and fee_cents<=item_cents),
 seller_cents bigint not null check(seller_cents>=0),
 source_charge text,
 disputed boolean not null default false,
 refunded_cents bigint not null default 0 check(refunded_cents>=0),
 picked_up_at timestamptz,
 buyer_confirmed_at timestamptz,
 transfer_id text unique,
 release_started_at timestamptz,
 released_at timestamptz,
 created_at timestamptz not null default now(),
 check(seller_cents+fee_cents=item_cents)
);
create table public.commerce_promotions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users,
 show_id text not null references public.loop_live_shows(id),
 kind text not null check(kind in ('quick','show')),
 amount_cents bigint not null check(amount_cents between 100 and 5000),
 request_id uuid not null,
 intent_id text unique,
 attempt integer not null default 1,
 refunded_cents bigint not null default 0 check(refunded_cents>=0),
 status text not null default 'pending' check(status in ('pending','paid','failed','refunded')),
 created_at timestamptz not null default now(),
 unique(user_id,request_id),
 check(kind<>'show' or amount_cents>=300)
);
create table public.commerce_platform_ledger (
 id bigint generated always as identity primary key,
 reference text not null unique,
 kind text not null check(kind in ('fee','promotion','refund')),
 amount_cents bigint not null,
 currency text not null default 'EUR' check(currency='EUR'),
 order_id uuid references public.commerce_orders,
 promotion_id uuid references public.commerce_promotions,
 created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['commerce_customers','commerce_payments','commerce_promotions','commerce_platform_ledger'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.commerce_platform_ledger_id_seq to service_role;
grant select on public.commerce_payments,public.commerce_promotions to authenticated;
create policy payments_participant on public.commerce_payments for select to authenticated using(exists(select 1 from public.commerce_orders o where o.id=order_id and auth.uid() in (o.buyer_id,o.seller_id)));
create policy promotions_own on public.commerce_promotions for select to authenticated using(user_id=auth.uid());
create index payments_release_due on public.commerce_payments(picked_up_at) where status='paid' and transfer_id is null and not disputed;
create unique index promotions_one_show on public.commerce_promotions(show_id) where kind='show' and status in ('pending','paid');

create function public.commerce_begin_promotion(p_user uuid,p_show text,p_kind text,p_amount bigint,p_request uuid) returns public.commerce_promotions
language plpgsql security definer set search_path=public as $$ declare p commerce_promotions; s jsonb; begin
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 select * into p from commerce_promotions where user_id=p_user and request_id=p_request;
 if found then
  if p.show_id<>p_show or p.kind<>p_kind or p.amount_cents<>p_amount then raise exception 'REQUEST_CONFLICT'; end if;
  return p;
 end if;
 select data into s from loop_live_shows where id=p_show for update;
 if not found or s->>'endedAt' is not null or (s->>'startsAt')::timestamptz+interval '3 hours'<now() then raise exception 'SHOW_ENDED'; end if;
 if p_kind='quick' and ((s->>'startsAt')::timestamptz>now() or coalesce((s->>'hostSeenAt')::timestamptz,'epoch')<now()-interval '2 minutes') then raise exception 'SHOW_NOT_LIVE'; end if;
 insert into commerce_promotions(user_id,show_id,kind,amount_cents,request_id) values(p_user,p_show,p_kind,p_amount,p_request) returning * into p;
 return p;
end $$;

-- Freeze cancellation as soon as a server-side payment attempt begins.
create or replace function public.commerce_checkout_guard() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status='awaiting_payment' and (
  exists(select 1 from commerce_checkout_sessions where order_id=old.id) or
  exists(select 1 from commerce_payments where order_id=old.id and status in ('pending','paid'))
 ) then raise exception 'CHECKOUT_IN_PROGRESS'; end if;
 return new;
end $$;

create function public.commerce_begin_charge(p_order uuid) returns public.commerce_payments
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; p commerce_payments; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.status<>'awaiting_payment' then raise exception 'ORDER_NOT_PAYABLE'; end if;
 insert into commerce_payments(order_id,item_cents,fee_cents,seller_cents)
 values(o.id,o.total_cents-o.shipping_cents,((o.total_cents-o.shipping_cents)*6+50)/100,o.total_cents-o.shipping_cents-((o.total_cents-o.shipping_cents)*6+50)/100)
 on conflict(order_id) do nothing;
 select * into p from commerce_payments where order_id=p_order;
 return p;
end $$;

create function public.commerce_settle_intent(p_event text,p_order uuid,p_intent text,p_charge text,p_amount bigint,p_currency text) returns void
language plpgsql security definer set search_path=public as $$ declare p commerce_payments; o commerce_orders; begin
 perform 1 from commerce_orders where id=p_order for update;
 select * into p from commerce_payments where order_id=p_order for update;
 select * into o from commerce_orders where id=p_order;
 if p.order_id is null or p.intent_id is distinct from p_intent or o.total_cents<>p_amount or p_currency<>'EUR' or p.status='refunded' then raise exception 'PAYMENT_MISMATCH'; end if;
 perform commerce_record_payment(p_event,p_order,p_amount,p_currency);
 perform commerce_fulfill_device(p_order);
 update commerce_payments set status='paid',source_charge=p_charge where order_id=p_order;
 insert into commerce_platform_ledger(reference,kind,amount_cents,order_id)
 values('fee:'||p_order,'fee',p.fee_cents,p_order) on conflict(reference) do nothing;
end $$;

-- The buyer explicitly confirms receipt and condition. No browser can create a transfer.
create or replace function public.commerce_confirm_delivery(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.buyer_id is distinct from auth.uid() then raise exception 'BUYER_ONLY'; end if;
 if o.status not in ('shipped','delivered') then raise exception 'SHIPMENT_REQUIRED'; end if;
 update commerce_orders set status='delivered' where id=p_order;
 update commerce_payments set buyer_confirmed_at=coalesce(buyer_confirmed_at,now()),picked_up_at=coalesce(picked_up_at,now()) where order_id=p_order;
end $$;

create function public.commerce_report_problem(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ begin
 perform 1 from commerce_orders where id=p_order and buyer_id=auth.uid() and status in ('paid','shipped','delivered') for update;
 if not found then raise exception 'BUYER_ONLY'; end if;
 update commerce_payments set disputed=true where order_id=p_order;
end $$;

-- Called only by the trusted carrier adapter or test worker, never the browser.
create function public.commerce_record_pickup(p_order uuid,p_at timestamptz) returns void
language plpgsql security definer set search_path=public as $$ begin
 if p_at is null or p_at>now() then raise exception 'INVALID_PICKUP'; end if;
 if not exists(select 1 from commerce_orders where id=p_order and status in ('shipped','delivered')) then raise exception 'SHIPMENT_REQUIRED'; end if;
 update commerce_payments set picked_up_at=coalesce(picked_up_at,p_at) where order_id=p_order;
end $$;

create function public.commerce_claim_release(p_order uuid) returns public.commerce_payments
language plpgsql security definer set search_path=public as $$ declare p commerce_payments; begin
 select * into p from commerce_payments where order_id=p_order for update;
 if not found or p.status<>'paid' or p.disputed or p.refunded_cents>0 or p.transfer_id is not null or p.source_charge is null or p.picked_up_at is null
  or (p.buyer_confirmed_at is null and now()<p.picked_up_at+interval '48 hours') then raise exception 'RELEASE_NOT_READY'; end if;
 update commerce_payments set release_started_at=coalesce(release_started_at,now()) where order_id=p_order;
 return p;
end $$;

create function public.commerce_record_refund(p_intent text,p_refunded bigint,p_disputed boolean default false) returns void
language plpgsql security definer set search_path=public as $$ declare p commerce_payments; begin
 select * into p from commerce_payments where intent_id=p_intent for update;
 if not found then return; end if;
 update commerce_payments set disputed=disputed or p_disputed,refunded_cents=greatest(refunded_cents,p_refunded),status=case when p_refunded>=(select total_cents from commerce_orders where id=p.order_id) then 'refunded' else status end where order_id=p.order_id;
 if p_refunded>0 then
  insert into commerce_platform_ledger(reference,kind,amount_cents,order_id)
  values('refund:'||p_intent||':'||p_refunded,'refund',-least(p.fee_cents,(p_refunded*6+50)/100)+least(p.fee_cents,(p.refunded_cents*6+50)/100),p.order_id) on conflict do nothing;
 end if;
 if p_refunded>=(select total_cents from commerce_orders where id=p.order_id) then update commerce_orders set status='refunded' where id=p.order_id; end if;
end $$;

create function public.commerce_settle_promotion(p_id uuid,p_intent text,p_amount bigint) returns void
language plpgsql security definer set search_path=public as $$ declare p commerce_promotions; s jsonb; event_id text; begin
 select * into p from commerce_promotions where id=p_id for update;
 if not found or p.intent_id is distinct from p_intent or p.amount_cents<>p_amount or p.status='refunded' then raise exception 'PAYMENT_MISMATCH'; end if;
 if p.status='paid' then return; end if;
 select data into s from loop_live_shows where id=p.show_id;
 update commerce_promotions set status='paid' where id=p_id;
 insert into commerce_platform_ledger(reference,kind,amount_cents,promotion_id) values('promotion:'||p_id,'promotion',p.amount_cents,p_id) on conflict do nothing;
 event_id:='stripe-boost-'||p_id;
 insert into loop_live_events(id,data) values(event_id,jsonb_build_object('id',event_id,'showId',p.show_id,'type','boost','userId',p.user_id,'userLabel','', 'at',now(),'lot',0,'amount',p.amount_cents/100.0,'text',p.kind)) on conflict(id) do nothing;
 insert into loop_transactions(id,data) values(event_id,jsonb_build_object('id',event_id,'type','promotion','userId',p.user_id,'deviceId','','deviceName','Promocija · '||coalesce(s->>'title','Subhasto'),'price',p.amount_cents/100.0,'fee',0,'amount',p.amount_cents/100.0,'buyerId',p.user_id,'buyerLabel','','sellerLabel','Subhasto','createdAt',now(),'isAuction',false)) on conflict(id) do nothing;
end $$;

-- Protect server-confirmed payment records and paid boosts from client fabrication.
create function public.commerce_refund_promotion(p_id uuid,p_amount bigint) returns void
language plpgsql security definer set search_path=public as $$ declare p commerce_promotions; begin
 select * into p from commerce_promotions where id=p_id for update;
 if not found or p_amount<=p.refunded_cents then return; end if;
 update commerce_promotions set status='refunded',refunded_cents=greatest(refunded_cents,p_amount) where id=p_id;
 delete from loop_live_events where id='stripe-boost-'||p_id;
 insert into commerce_platform_ledger(reference,kind,amount_cents,promotion_id) values('promotion-refund:'||p_id||':'||p_amount,'refund',-least(p.amount_cents,p_amount)+least(p.amount_cents,p.refunded_cents),p_id) on conflict do nothing;
end $$;

-- Protect server-confirmed payment records and paid boosts from client fabrication.
create function public.commerce_protect_stripe_records() returns trigger
language plpgsql set search_path=pg_catalog as $$ begin
 if current_user not in ('postgres','service_role','supabase_admin') then
  if TG_OP<>'INSERT' and old.id like 'stripe-%' then raise exception 'SERVER_ONLY'; end if;
  if TG_OP<>'DELETE' and (new.id like 'stripe-%' or (TG_TABLE_NAME='loop_live_events' and new.data->>'type'='boost')) then raise exception 'SERVER_ONLY'; end if;
 end if;
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
create trigger protect_stripe_transactions before insert or update or delete on public.loop_transactions for each row execute function public.commerce_protect_stripe_records();
create trigger protect_stripe_boosts before insert or update or delete on public.loop_live_events for each row execute function public.commerce_protect_stripe_records();

create or replace function public.subhasto_integration_secrets() returns jsonb
language sql stable security definer set search_path=pg_catalog as $$
 select coalesce(jsonb_object_agg(name,decrypted_secret),'{}'::jsonb) from vault.decrypted_secrets where name in (
 'STRIPE_RESTRICTED_KEY','STRIPE_SECRET_KEY','STRIPE_PUBLISHABLE_KEY','STRIPE_WEBHOOK_SECRET','STRIPE_RELEASE_JOB_SECRET','LIVEKIT_URL','LIVEKIT_API_KEY','LIVEKIT_API_SECRET')
$$;
do $$ declare sig text; begin
 foreach sig in array array['commerce_fulfill_device(uuid)','commerce_begin_charge(uuid)','commerce_refund_promotion(uuid,bigint)','commerce_begin_promotion(uuid,text,text,bigint,uuid)','commerce_settle_intent(text,uuid,text,text,bigint,text)','commerce_record_pickup(uuid,timestamptz)','commerce_claim_release(uuid)','commerce_record_refund(text,bigint,boolean)','commerce_settle_promotion(uuid,text,bigint)'] loop
  execute 'revoke all on function public.'||sig||' from public,anon,authenticated';
  execute 'grant execute on function public.'||sig||' to service_role';
 end loop;
end $$;
revoke all on function public.commerce_report_problem(uuid),public.commerce_protect_stripe_records() from public,anon,authenticated;
grant execute on function public.commerce_report_problem(uuid) to authenticated;
commit;
