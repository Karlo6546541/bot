-- Aukcije (klasična, holandska, zatvorena) se zaključuju na poslužitelju i
-- naplaćuju preko Stripea kao i ostale narudžbe:
--  * auction_settle(id) / auction_settle_due(): istekla aukcija → pobjednik
--    dobiva narudžbu (commerce_orders, awaiting_payment); bez ponuda → unsold.
--    pg_cron svake minute, pa aukcija završi i kad nitko nema otvorenu aplikaciju.
--  * auction_take_dutch(id, max): holandska kupnja atomski (jedan kupac),
--    cijena se računa na poslužitelju, traži se spremljena kartica.
--  * Narudžba aukcije: provizija 10 % samo od razlike iznad početne cijene
--    (holandska: iznad najniže), kao u aplikaciji.
--  * Klijent više ne smije sam zatvoriti aukciju (sold/unsold) ni mijenjati
--    završenu aukciju.
begin;

alter table public.commerce_orders add column if not exists source_auction text;
alter table public.commerce_orders add column if not exists auction_base_cents bigint;
create unique index if not exists commerce_orders_source_auction on public.commerce_orders(source_auction) where source_auction is not null;

-- Vrijeme iz zapisa aukcije: s oznakom zone (Z/+01:00) doslovno, bez nje
-- (stariji zapisi iz preglednika) kao lokalno hrvatsko vrijeme.
create or replace function public.auction_ts(p text) returns timestamptz
language sql immutable set search_path=pg_catalog as $$
 select case when p ~ '(Z|[+-][0-9]{2}:?[0-9]{2})$' then p::timestamptz
  else p::timestamp at time zone 'Europe/Zagreb' end $$;

-- Provizija narudžbe: aukcija 10 % razlike iznad osnovice, inače kao do sada (6 %).
create or replace function public.commerce_order_fee_cents(o public.commerce_orders) returns bigint
language sql immutable set search_path=public as $$
 select case when o.source_auction is not null
  then greatest(0,(o.total_cents-o.shipping_cents-coalesce(o.auction_base_cents,0))*10+50)/100
  else ((o.total_cents-o.shipping_cents)*6+50)/100 end $$;

create or replace function public.commerce_begin_charge(p_order uuid) returns public.commerce_payments
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; p commerce_payments; fee bigint; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.status<>'awaiting_payment' then raise exception 'ORDER_NOT_PAYABLE'; end if;
 fee:=commerce_order_fee_cents(o);
 insert into commerce_payments(order_id,item_cents,fee_cents,seller_cents)
 values(o.id,o.total_cents-o.shipping_cents,fee,o.total_cents-o.shipping_cents-fee)
 on conflict(order_id) do nothing;
 select * into p from commerce_payments where order_id=p_order;
 return p;
end $$;

create or replace function public.commerce_fulfill_device(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; d jsonb; bought text; tx jsonb; item bigint; fee bigint; begin
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
 item:=o.total_cents-o.shipping_cents; fee:=commerce_order_fee_cents(o);
 tx:=jsonb_build_object('deviceId',bought,'deviceName',trim(coalesce(d->>'name','')||' '||coalesce(d->>'model','')),'price',item/100.0,'fee',0,'amount',o.total_cents/100.0,'buyerId',o.buyer_id,'sellerId',o.seller_id,'buyerLabel','','sellerLabel','','createdAt',now(),'isAuction',o.source_auction is not null);
 insert into loop_transactions(id,data) values('stripe-buy-'||o.id,tx||jsonb_build_object('id','stripe-buy-'||o.id,'type','buy','userId',o.buyer_id));
 insert into loop_transactions(id,data) values('stripe-sale-'||o.id,tx||jsonb_build_object('id','stripe-sale-'||o.id,'type','sell','userId',o.seller_id,'fee',fee/100.0,'amount',(item-fee)/100.0));
end $$;

-- Narudžba za pobjednika (zove se unutar zaključane aukcije).
create or replace function public.auction_create_order(p_id text,a jsonb,p_buyer uuid,p_cents bigint) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; d jsonb; base bigint; begin
 select * into o from commerce_orders where source_auction=p_id;
 if found then return o; end if;
 select data into d from loop_devices where id=a->>'deviceId';
 base:=round(coalesce(case when a->>'kind'='dutch' then (a->>'floorPrice')::numeric else (a->>'startPrice')::numeric end,0)*100);
 insert into commerce_orders(buyer_id,seller_id,quantity,total_cents,request_id,source_device,source_snapshot,source_auction,auction_base_cents)
 values(p_buyer,(a->>'sellerId')::uuid,1,p_cents,gen_random_uuid(),a->>'deviceId',coalesce(d,'{}'::jsonb),p_id,base)
 returning * into o;
 return o;
end $$;

-- Zaključi jednu isteklu aukciju (idempotentno). Vraća narudžbu pobjednika ili null.
create or replace function public.auction_settle(p_id text) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare a jsonb; top jsonb; o commerce_orders; begin
 select data into a from loop_auctions where id=p_id for update;
 if not found then return null; end if;
 if a->>'status'<>'active' then
  select * into o from commerce_orders where source_auction=p_id; return o;
 end if;
 if auction_ts(a->>'endsAt') > now() then return null; end if;
 -- Zadnja ponuda je uvijek najviša (zatvorena: ponude su složene po iznosu).
 top:=a->'bids'->-1;
 if top is null or a->>'kind'='dutch' then
  update loop_auctions set data=a||jsonb_build_object('status','unsold'),updated_at=now() where id=p_id;
  return null;
 end if;
 begin
  o:=auction_create_order(p_id,a,(top->>'userId')::uuid,round((top->>'amount')::numeric*100)::bigint);
 exception when others then
  -- Nevažeći pobjednik/prodavač (npr. obrisan račun): aukcija se otkazuje.
  update loop_auctions set data=a||jsonb_build_object('status','cancelled'),updated_at=now() where id=p_id;
  return null;
 end;
 update loop_auctions set data=a||jsonb_build_object('status','sold'),updated_at=now() where id=p_id;
 return o;
end $$;

create or replace function public.auction_settle_due() returns integer
language plpgsql security definer set search_path=public as $$ declare r record; n integer:=0; begin
 for r in select id from loop_auctions where data->>'status'='active'
   and auction_ts(data->>'endsAt')<=now() limit 200 loop
  perform auction_settle(r.id); n:=n+1;
 end loop;
 return n;
end $$;

-- Holandska: prvi kupac s karticom kupuje po cijeni koju računa poslužitelj
-- (nikad višoj od one koju je kupac potvrdio).
create or replace function public.auction_take_dutch(p_id text,p_max numeric) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare a jsonb; o commerce_orders; t0 timestamptz; t1 timestamptz; frac numeric; price numeric; me text; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 me:=auth.uid()::text;
 if not exists(select 1 from commerce_customers where user_id=auth.uid() and consent_at is not null) then raise exception 'CARD_REQUIRED'; end if;
 select data into a from loop_auctions where id=p_id for update;
 if not found or a->>'kind'<>'dutch' then raise exception 'NOT_DUTCH'; end if;
 if a->>'status'<>'active' or jsonb_array_length(coalesce(a->'bids','[]'::jsonb))>0 then raise exception 'ALREADY_SOLD'; end if;
 if a->>'sellerId'=me then raise exception 'OWN_AUCTION'; end if;
 t0:=auction_ts(a->>'createdAt');
 t1:=auction_ts(a->>'endsAt');
 if now()>=t1 then raise exception 'AUCTION_ENDED'; end if;
 frac:=greatest(0,least(1,extract(epoch from now()-t0)/nullif(extract(epoch from t1-t0),0)));
 price:=round((a->>'startPrice')::numeric-((a->>'startPrice')::numeric-(a->>'floorPrice')::numeric)*coalesce(frac,1),2);
 if p_max is not null and price>p_max+0.001 then raise exception 'PRICE_CHANGED'; end if;
 o:=auction_create_order(p_id,a,auth.uid(),round(price*100)::bigint);
 update loop_auctions set data=a||jsonb_build_object('status','sold','bids',jsonb_build_array(jsonb_build_object('userId',me,'userLabel',coalesce((select data->>'username' from loop_users where id=me),''),'amount',price,'time',to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')))),updated_at=now() where id=p_id;
 return o;
end $$;

-- Klijent ne smije sam završiti aukciju ni dirati završenu.
create or replace function public.auction_client_guard() returns trigger
language plpgsql set search_path=public as $$ begin
 if current_user in ('postgres','service_role','supabase_admin') then return new; end if;
 if tg_op='UPDATE' then
  if old.data->>'status'<>'active' and new.data is distinct from old.data then raise exception 'AUCTION_CLOSED'; end if;
  if new.data->>'status' in ('sold','unsold') then raise exception 'AUCTION_SETTLED_BY_SERVER'; end if;
  if (new.data->>'kind') is distinct from (old.data->>'kind') or (new.data->>'sellerId') is distinct from (old.data->>'sellerId')
   or (new.data->>'startPrice') is distinct from (old.data->>'startPrice') or (new.data->>'floorPrice') is distinct from (old.data->>'floorPrice')
   then raise exception 'AUCTION_TERMS_LOCKED'; end if;
  if new.data->>'kind'='dutch' and jsonb_array_length(coalesce(new.data->'bids','[]'::jsonb))>0 then raise exception 'NOT_DUTCH_BID'; end if;
 elsif tg_op='INSERT' then
  if coalesce(new.data->>'status','active')<>'active' then raise exception 'AUCTION_SETTLED_BY_SERVER'; end if;
 end if;
 return new;
end $$;
drop trigger if exists auction_client_guard on public.loop_auctions;
create trigger auction_client_guard before insert or update on public.loop_auctions for each row execute function public.auction_client_guard();

revoke all on function public.auction_create_order(text,jsonb,uuid,bigint) from public,anon,authenticated;
revoke all on function public.commerce_order_fee_cents(public.commerce_orders) from public,anon,authenticated;
revoke all on function public.auction_settle_due() from public,anon,authenticated;
grant execute on function public.auction_settle_due() to service_role;
revoke all on function public.auction_settle(text) from public,anon;
grant execute on function public.auction_settle(text) to authenticated,service_role;
revoke all on function public.auction_take_dutch(text,numeric) from public,anon;
grant execute on function public.auction_take_dutch(text,numeric) to authenticated;
commit;

-- Zaključivanje isteklih aukcija svake minute (bez otvorene aplikacije).
select cron.unschedule(jobid) from cron.job where jobname='subhasto-auction-settle';
select cron.schedule('subhasto-auction-settle','* * * * *','select public.auction_settle_due()');
