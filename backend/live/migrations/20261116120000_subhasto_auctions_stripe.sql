-- Subhasto: aukcije preko poslužitelja i Stripea. Primijeniti NAKON
-- 20261103000000_subhasto_order_fixes.sql i
-- 20261111100000_subhasto_auction_settlement.sql.
--
--  1. Nove aukcije su samo klasične (zatvorena i nizozemska se više ne mogu objaviti).
--  2. Ponuda traži povezanu karticu (commerce_customers.consent_at); kupac s
--     dva neplaćena dobitka u 90 dana ne može licitirati.
--  3. Kraj aukcije: narudžba = najviša ponuda + dostava kurirom; obavijesti
--     šalje poslužitelj. "Kupi odmah" na aukciji zaključuje odmah.
--  4. Neplaćena narudžba aukcije: 24 h (ostale 30 min), zatim poništenje,
--     opomena kupcu i obavijest prodavaču.
--  5. Novac drži Stripe na povezanom računu prodavača (destination charge):
--     commerce_payments.destination_account + isplata (payout_id) nakon
--     dostave i potvrde kupca ili 48 h. Stare naplate (bez
--     destination_account) i dalje idu starim prijenosom.
begin;

-- 5. Model naplate ----------------------------------------------------------
alter table public.commerce_payments add column if not exists destination_account text;
alter table public.commerce_payments add column if not exists payout_id text;
alter table public.commerce_payments add column if not exists paid_out_at timestamptz;
create unique index if not exists commerce_payments_payout on public.commerce_payments(payout_id) where payout_id is not null;
alter table public.commerce_sellers add column if not exists transfers_active boolean not null default false;
alter table public.commerce_sellers add column if not exists checked_at timestamptz;

-- 2. Opomene za neplaćene dobitke -------------------------------------------
create table if not exists public.commerce_bid_strikes (
 auction_id text primary key,
 user_id uuid not null,
 order_id uuid,
 created_at timestamptz not null default now()
);
alter table public.commerce_bid_strikes enable row level security;
revoke all on public.commerce_bid_strikes from public,anon,authenticated;
grant all on public.commerce_bid_strikes to service_role;
grant select on public.commerce_bid_strikes to authenticated;
drop policy if exists bid_strikes_own on public.commerce_bid_strikes;
create policy bid_strikes_own on public.commerce_bid_strikes for select to authenticated using(user_id=auth.uid());
create index if not exists commerce_bid_strikes_user on public.commerce_bid_strikes(user_id,created_at);

-- Obavijest u aplikaciji (isti oblik kao AppNotification.toMap).
create or replace function public.srv_notify(p_user text,p_kind text,p_args jsonb,p_target text) returns void
language plpgsql security definer set search_path=public as $$ declare nid text:='srv-'||gen_random_uuid(); begin
 if p_user is null or not exists(select 1 from loop_users where id=p_user) then return; end if;
 insert into loop_notifications(id,data) values(nid,jsonb_build_object('id',nid,'userId',p_user,'kind',p_kind,
  'args',coalesce(p_args,'[]'::jsonb),'targetId',p_target,'read',false,
  'createdAt',to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
end $$;
revoke all on function public.srv_notify(text,text,jsonb,text) from public,anon,authenticated;

-- Provizija: aukcija 10 % razlike iznad osnovice; ostalo kao u aplikaciji (5 %).
create or replace function public.commerce_order_fee_cents(o public.commerce_orders) returns bigint
language sql immutable set search_path=public as $$
 select case when o.source_auction is not null
  then greatest(0,(o.total_cents-o.shipping_cents-coalesce(o.auction_base_cents,0))*10+50)/100
  else commerce_fee_cents(o.total_cents-o.shipping_cents) end $$;

-- 3. Narudžba pobjednika: ponuda + dostava kurirom (adresa iz profila kupca;
--    kupac je može promijeniti dok paket nije poslan). --------------------
create or replace function public.auction_create_order(p_id text,a jsonb,p_buyer uuid,p_cents bigint) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; d jsonb; base bigint; ship bigint; addr text; begin
 select * into o from commerce_orders where source_auction=p_id;
 if found then return o; end if;
 select data into d from loop_devices where id=a->>'deviceId';
 base:=round(coalesce(case when a->>'kind'='dutch' then (a->>'floorPrice')::numeric else (a->>'startPrice')::numeric end,0)*100);
 ship:=case when d->>'file' is not null then 0 else commerce_shipping_cents('courier',d->>'parcelSize') end;
 insert into commerce_orders(buyer_id,seller_id,quantity,total_cents,shipping_cents,request_id,source_device,source_snapshot,source_auction,auction_base_cents)
 values(p_buyer,(a->>'sellerId')::uuid,1,p_cents+ship,ship,gen_random_uuid(),a->>'deviceId',coalesce(d,'{}'::jsonb),p_id,base)
 returning * into o;
 select nullif(trim(data->>'address'),'') into addr from loop_users where id=p_buyer::text;
 insert into commerce_shipments(order_id,method,destination)
 values(o.id,case when d->>'file' is not null then 'pickup' else 'courier' end,
  case when d->>'file' is not null then '{}'::jsonb else jsonb_build_object('address',coalesce(left(addr,500),'')) end)
 on conflict(order_id) do nothing;
 return o;
end $$;

create or replace function public.auction_settle(p_id text) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare a jsonb; top jsonb; o commerce_orders; early boolean; loser text; begin
 select data into a from loop_auctions where id=p_id for update;
 if not found then return null; end if;
 if coalesce(a->>'status','')<>'active' then
  select * into o from commerce_orders where source_auction=p_id; return o;
 end if;
 top:=a->'bids'->-1;
 -- "Kupi odmah" na klasičnoj aukciji: ponuda na toj cijeni zaključuje odmah.
 early:=coalesce(a->>'kind','classic')<>'dutch' and a->>'buyNowPrice' is not null and top is not null
  and (top->>'amount')::numeric>=(a->>'buyNowPrice')::numeric;
 if auction_ts(a->>'endsAt')>now() and not early then return null; end if;
 if top is null or a->>'kind'='dutch' then
  update loop_auctions set data=a||jsonb_build_object('status','unsold'),updated_at=now() where id=p_id;
  perform srv_notify(a->>'sellerId','auctionUnsold',jsonb_build_array(a->>'deviceName'),p_id);
  return null;
 end if;
 begin
  o:=auction_create_order(p_id,a,(top->>'userId')::uuid,round((top->>'amount')::numeric*100)::bigint);
 exception when others then
  -- Nevažeći pobjednik/prodavač/predmet: aukcija se otkazuje, ništa se ne naplaćuje.
  update loop_auctions set data=a||jsonb_build_object('status','cancelled'),updated_at=now() where id=p_id;
  return null;
 end;
 update loop_auctions set data=a||jsonb_build_object('status','sold'),updated_at=now() where id=p_id;
 perform srv_notify(top->>'userId','auctionWon',jsonb_build_array(a->>'deviceName',(top->>'amount')::numeric),p_id);
 perform srv_notify(a->>'sellerId','auctionSold',jsonb_build_array(a->>'deviceName',(top->>'amount')::numeric),p_id);
 for loser in select distinct b->>'userId' from jsonb_array_elements(a->'bids') b where b->>'userId'<>top->>'userId' loop
  perform srv_notify(loser,'auctionLost',jsonb_build_array(a->>'deviceName'),p_id);
 end loop;
 return o;
end $$;

-- Istekle aukcije i one na kojima je ponuda dosegla "Kupi odmah".
create or replace function public.auction_settle_due() returns integer
language plpgsql security definer set search_path=public as $$ declare r record; n integer:=0; begin
 for r in select id from loop_auctions where data->>'status'='active'
   and (auction_ts(data->>'endsAt')<=now()
    or (data->>'buyNowPrice' is not null and coalesce(data->>'kind','classic')<>'dutch'
        and (data->'bids'->-1->>'amount')::numeric>=(data->>'buyNowPrice')::numeric)) limit 200 loop
  perform auction_settle(r.id); n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.auction_settle_due() from public,anon,authenticated;
grant execute on function public.auction_settle_due() to service_role;

-- Nizozemska (samo postojeće aukcije od prije): kao do sada, uz obavijesti.
create or replace function public.auction_take_dutch(p_id text,p_max numeric) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare a jsonb; o commerce_orders; t0 timestamptz; t1 timestamptz; frac numeric; price numeric; me text; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 me:=auth.uid()::text;
 if not exists(select 1 from commerce_customers where user_id=auth.uid() and consent_at is not null) then raise exception 'CARD_REQUIRED'; end if;
 if (select count(*) from commerce_bid_strikes where user_id=auth.uid() and created_at>now()-interval '90 days')>=2 then raise exception 'BIDDING_SUSPENDED'; end if;
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
 perform srv_notify(a->>'sellerId','auctionSold',jsonb_build_array(a->>'deviceName',price),p_id);
 return o;
end $$;

-- 1. + 2. Klijent: bez zatvorenih aukcija, ponuda samo s karticom ------------
-- Pomoćne provjere (tablice kupaca nisu čitljive klijentu).
create or replace function public.auction_has_card(p_user text) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from commerce_customers c where c.user_id::text=p_user and c.consent_at is not null) $$;
create or replace function public.auction_bidding_suspended(p_user uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select (select count(*) from commerce_bid_strikes where user_id=p_user and created_at>now()-interval '90 days')>=2 $$;
revoke all on function public.auction_has_card(text) from public,anon;
revoke all on function public.auction_bidding_suspended(uuid) from public,anon;
grant execute on function public.auction_has_card(text),public.auction_bidding_suspended(uuid) to authenticated,service_role;

-- Okidač radi s pravima pozivatelja: poslužiteljske funkcije (security
-- definer, vlasnik postgres) prolaze, klijent ne može sam zaključiti aukciju.
create or replace function public.auction_client_guard() returns trigger
language plpgsql set search_path=public as $$ declare n_old integer; n_new integer; b jsonb; begin
 if current_user in ('postgres','service_role','supabase_admin') then return new; end if;
 -- Nove aukcije su samo klasične (zatvorena i nizozemska se više ne nude).
 if tg_op='INSERT' and coalesce(new.data->>'kind','classic')<>'classic' then raise exception 'AUCTION_KIND_UNAVAILABLE'; end if;
 if tg_op='UPDATE' then
  if coalesce(old.data->>'status','')<>'active' and new.data is distinct from old.data then raise exception 'AUCTION_CLOSED'; end if;
  if new.data->>'status' in ('sold','unsold') then raise exception 'AUCTION_SETTLED_BY_SERVER'; end if;
  if (new.data->>'kind') is distinct from (old.data->>'kind') or (new.data->>'sellerId') is distinct from (old.data->>'sellerId')
   or (new.data->>'startPrice') is distinct from (old.data->>'startPrice') or (new.data->>'floorPrice') is distinct from (old.data->>'floorPrice')
   then raise exception 'AUCTION_TERMS_LOCKED'; end if;
  n_old:=jsonb_array_length(coalesce(old.data->'bids','[]'::jsonb));
  n_new:=jsonb_array_length(coalesce(new.data->'bids','[]'::jsonb));
  if new.data->>'kind'='dutch' and n_new>0 then raise exception 'NOT_DUTCH_BID'; end if;
  if n_new>n_old then
   -- Svaki novi ponuđač (i automatska ponuda u tuđe ime) mora imati karticu.
   for b in select e from jsonb_array_elements(new.data->'bids') with ordinality as t(e,i) where i>n_old loop
    if not auction_has_card(b->>'userId') then raise exception 'CARD_REQUIRED'; end if;
   end loop;
   if auction_bidding_suspended(auth.uid()) then raise exception 'BIDDING_SUSPENDED'; end if;
  end if;
 elsif tg_op='INSERT' then
  if coalesce(new.data->>'status','active')<>'active' then raise exception 'AUCTION_SETTLED_BY_SERVER'; end if;
  if jsonb_array_length(coalesce(new.data->'bids','[]'::jsonb))>0 then raise exception 'AUCTION_TERMS_LOCKED'; end if;
 end if;
 return new;
end $$;

-- Plaćena narudžba: mijenja se samo odredište (cijena dostave je naplaćena),
-- a zapis dostave u aplikaciji prati promjenu dok paket nije poslan.
create or replace function public.commerce_choose_shipping(p_order uuid,p_method text,p_destination jsonb) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; l commerce_delivery_locations; destination jsonb; cents bigint; cur commerce_shipments; dest text; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or auth.uid() is null or o.buyer_id<>auth.uid() then raise exception 'BUYER_ONLY'; end if;
 if o.status not in ('awaiting_payment','paid') then raise exception 'ORDER_LOCKED'; end if;
 if p_method='boxnow' then
  select * into l from commerce_delivery_locations where id=p_destination->>'locker_id' and active;
  if not found then raise exception 'LOCKER_UNAVAILABLE'; end if;
  destination:=jsonb_build_object('locker_id',l.id,'provider',l.provider,'provider_location_id',l.provider_id,'name',l.name,'address',l.address,'postal_code',l.postal_code,'city',l.city,'country_code',l.country_code,'is_demo',l.is_demo);
 elsif p_method='courier' then
  if coalesce(length(trim(p_destination->>'address')),0)=0 then raise exception 'ADDRESS_REQUIRED'; end if;
  destination:=jsonb_build_object('address',left(trim(p_destination->>'address'),500));
 elsif p_method='pickup' then destination:='{}'::jsonb;
 else raise exception 'INVALID_SHIPPING_METHOD'; end if;
 cents:=commerce_shipping_cents(p_method,o.source_snapshot->>'parcelSize');
 select * into cur from commerce_shipments where order_id=p_order;
 if o.status='awaiting_payment' and not exists(select 1 from commerce_payments where order_id=o.id) then
  update commerce_orders set shipping_cents=cents,total_cents=(o.total_cents-o.shipping_cents)+cents where id=o.id;
 elsif cur.order_id is not null and cur.method<>p_method then
  raise exception 'SHIPPING_METHOD_LOCKED';
 end if;
 insert into commerce_shipments(order_id,method,destination) values(p_order,p_method,destination)
 on conflict(order_id) do update set method=excluded.method,destination=excluded.destination,updated_at=now();
 dest:=case p_method when 'boxnow' then concat_ws(', ',destination->>'name',destination->>'address',destination->>'city')
  when 'courier' then destination->>'address' else null end;
 update loop_deliveries set data=data||jsonb_build_object('destination',dest),updated_at=now()
  where id='del-stripe-sale-'||o.id and data->>'handedOverAt' is null;
end $$;

-- Plaćena narudžba -> predaja predmeta + zapis dostave ("Dostave" u aplikaciji).
create or replace function public.commerce_fulfill_device(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; d jsonb; bought text; tx jsonb; item bigint; fee bigint; s commerce_shipments; dest text; m text; begin
 select * into o from commerce_orders where id=p_order for update;
 if o.source_device is null then return; end if;
 if exists(select 1 from loop_transactions where id='stripe-buy-'||o.id) then return; end if;
 select data into d from loop_devices where id=o.source_device for update;
 if d is null or d->>'ownerId' is distinct from o.seller_id::text then raise exception 'LISTING_CHANGED'; end if;
 bought:=o.source_device;
 if d->>'file' is null then
  if coalesce((d->>'quantity')::integer,1)>1 and o.source_auction is null then
   bought:='stripe-item-'||o.id;
   insert into loop_devices(id,data) values(bought,d||jsonb_build_object('id',bought,'ownerId',o.buyer_id,'listPrice',null,'listedAt',null,'quantity',1,'discountPercent',0,'discountUntil',null));
   update loop_devices set data=d||jsonb_build_object('quantity',(d->>'quantity')::integer-1) where id=o.source_device;
  else update loop_devices set data=d||jsonb_build_object('ownerId',o.buyer_id,'listPrice',null,'listedAt',null,'quantity',1,'discountPercent',0,'discountUntil',null) where id=o.source_device;
  end if;
 end if;
 if o.source_auction is null then
  update loop_bargains set data=data||jsonb_build_object('status','used','updatedAt',now())
   where data->>'deviceId'=o.source_device and data->>'buyerId'=o.buyer_id::text and data->>'status'='accepted';
 end if;
 item:=o.total_cents-o.shipping_cents; fee:=commerce_order_fee_cents(o);
 tx:=jsonb_build_object('deviceId',bought,'deviceName',trim(coalesce(d->>'name','')||' '||coalesce(d->>'model','')),'price',item/100.0,'fee',0,'amount',o.total_cents/100.0,'buyerId',o.buyer_id,'sellerId',o.seller_id,'buyerLabel','','sellerLabel','','createdAt',now(),'isAuction',o.source_auction is not null);
 insert into loop_transactions(id,data) values('stripe-buy-'||o.id,tx||jsonb_build_object('id','stripe-buy-'||o.id,'type','buy','userId',o.buyer_id));
 insert into loop_transactions(id,data) values('stripe-sale-'||o.id,tx||jsonb_build_object('id','stripe-sale-'||o.id,'type','sell','userId',o.seller_id,'fee',fee/100.0,'amount',(item-fee)/100.0));
 select * into s from commerce_shipments where order_id=o.id;
 if d->>'file' is null and found then
  m:=case s.method when 'boxnow' then 'parcelLocker' else s.method end;
  dest:=case s.method when 'boxnow' then concat_ws(', ',s.destination->>'name',s.destination->>'address',s.destination->>'city')
   when 'courier' then s.destination->>'address' else null end;
  insert into loop_deliveries(id,data) values('del-stripe-sale-'||o.id,jsonb_build_object(
   'id','del-stripe-sale-'||o.id,'deviceId',bought,'deviceName',trim(coalesce(d->>'name','')||' '||coalesce(d->>'model','')),
   'buyerId',o.buyer_id,'sellerId',o.seller_id,'createdAt',now(),'startedAt',now(),'method',m,'destination',dest,
   'cost',o.shipping_cents/100.0,'fromAuction',o.source_auction is not null,'reviewed',false,
   'trackingNumber','SUBH-'||upper(substr(md5(o.id::text),1,8)),
   'dropOffPin',case when s.method='boxnow' then lpad((floor(random()*1000000))::int::text,6,'0') end,
   'pickupPin',case when s.method='boxnow' then lpad((floor(random()*1000000))::int::text,6,'0') end))
  on conflict(id) do nothing;
 end if;
end $$;

-- 4. Rok plaćanja: aukcija 24 h, ostalo 30 min ------------------------------
create or replace function public.commerce_expire_order(p_order uuid) returns boolean
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; a jsonb; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.status<>'awaiting_payment' then return false; end if;
 if exists(select 1 from commerce_checkout_sessions where order_id=o.id) then return false; end if;
 if exists(select 1 from commerce_payments where order_id=o.id and status in ('paid','refunded')) then return false; end if;
 update commerce_payments set status='failed' where order_id=o.id and status='pending';
 update commerce_orders set status='cancelled' where id=o.id;
 update commerce_products set stock=stock+o.quantity where id=o.product_id;
 update live_awards set status='cancelled' where lot_id=o.award_lot_id;
 if o.source_auction is not null then
  select data into a from loop_auctions where id=o.source_auction for update;
  if a is not null then
   -- Predmet ostaje prodavaču (nije ni prešao kupcu); može ga ponovno ponuditi.
   update loop_auctions set data=a||jsonb_build_object('status','unsold','unpaid',true),updated_at=now() where id=o.source_auction;
   perform srv_notify(o.seller_id::text,'auctionUnpaid',jsonb_build_array(a->>'deviceName'),o.source_auction);
   insert into commerce_bid_strikes(auction_id,user_id,order_id) values(o.source_auction,o.buyer_id,o.id) on conflict do nothing;
   perform srv_notify(o.buyer_id::text,'bidStrike',jsonb_build_array(a->>'deviceName'),o.source_auction);
  end if;
 end if;
 return true;
end $$;

create or replace function public.commerce_expire_orders(p_idle interval default interval '30 minutes') returns integer
language plpgsql security definer set search_path=public as $$ declare r record; n integer:=0; begin
 for r in select id from commerce_orders ord where status='awaiting_payment'
   and created_at<now()-(case when ord.source_auction is not null then interval '24 hours' else p_idle end)
   and not exists(select 1 from commerce_payments p where p.order_id=ord.id and p.intent_id is not null) loop
  if commerce_expire_order(r.id) then n:=n+1; end if;
 end loop;
 return n;
end $$;

create or replace function public.commerce_stuck_orders(p_idle interval default interval '2 hours') returns table(order_id uuid,intent_id text)
language sql stable security definer set search_path=public as $$
 select o.id,p.intent_id from commerce_orders o join commerce_payments p on p.order_id=o.id
 where o.status='awaiting_payment' and p.status='pending' and p.intent_id is not null
  and o.created_at<now()-(case when o.source_auction is not null then interval '24 hours' else p_idle end)
 order by o.created_at limit 20 $$;

-- Kupac kojem automatska naplata nije prošla: obavijest (jednom po narudžbi).
create or replace function public.auction_payment_due(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order;
 if not found or o.source_auction is null or o.status<>'awaiting_payment' then return; end if;
 if exists(select 1 from loop_notifications where data->>'targetId'=o.source_auction and data->>'kind'='auctionPaymentDue' and data->>'userId'=o.buyer_id::text) then return; end if;
 perform srv_notify(o.buyer_id::text,'auctionPaymentDue',jsonb_build_array(coalesce(o.source_snapshot->>'name',''),o.total_cents/100.0),o.source_auction);
end $$;

-- 5. Oslobađanje: dostavljeno + potvrda kupca ili 48 h; vrijedi za oba modela.
create or replace function public.commerce_claim_release(p_order uuid) returns public.commerce_payments
language plpgsql security definer set search_path=public as $$ declare p commerce_payments; begin
 select * into p from commerce_payments where order_id=p_order for update;
 if not found or p.status<>'paid' or p.disputed or p.refunded_cents>0 or p.transfer_id is not null or p.payout_id is not null
  or p.source_charge is null or p.picked_up_at is null
  or (p.buyer_confirmed_at is null and now()<p.picked_up_at+interval '48 hours') then raise exception 'RELEASE_NOT_READY'; end if;
 update commerce_payments set release_started_at=coalesce(release_started_at,now()) where order_id=p_order;
 return p;
end $$;

-- 6. Dostava u aplikaciji (loop_deliveries, id del-stripe-sale-<narudžba>)
--    upravlja narudžbom: prodavač preda paket -> shipped; kupac potvrdi
--    primitak -> delivered + oslobađanje; spor -> zadržavanje; prihvaćen
--    povrat -> zahtjev za povrat na karticu (izvršava stripe-release).
alter table public.commerce_payments add column if not exists refund_requested_at timestamptz;
create or replace function public.commerce_delivery_sync() returns trigger
language plpgsql security definer set search_path=public as $$ declare oid uuid; me text:=auth.uid()::text; ds_old text; ds_new text;
 -- Uloga zahtjeva (SET ROLE) ostaje vidljiva i unutar security definer funkcije.
 client boolean:=coalesce(current_setting('role',true),'') in ('authenticated','anon'); begin
 if new.id not like 'del-stripe-sale-%' then return new; end if;
 begin oid:=substr(new.id,17)::uuid; exception when others then return new; end;
 ds_old:=old.data->'dispute'->>'status'; ds_new:=new.data->'dispute'->>'status';
 if client then
  if new.data->>'confirmedAt' is not null and old.data->>'confirmedAt' is null and me is distinct from old.data->>'buyerId' then raise exception 'BUYER_ONLY'; end if;
  if new.data->>'handedOverAt' is not null and old.data->>'handedOverAt' is null and me is distinct from old.data->>'sellerId' then raise exception 'SELLER_ONLY'; end if;
  if ds_new='refunded' and ds_old is distinct from 'refunded' and me is not distinct from old.data->>'buyerId' then raise exception 'SELLER_OR_SUPPORT_ONLY'; end if;
  if ds_new='rejected' and ds_old is distinct from 'rejected' and (me is null or me in (old.data->>'buyerId',old.data->>'sellerId')) then raise exception 'SUPPORT_ONLY'; end if;
  if (new.data->>'buyerId') is distinct from (old.data->>'buyerId') or (new.data->>'sellerId') is distinct from (old.data->>'sellerId') then raise exception 'SERVER_ONLY'; end if;
 end if;
 if new.data->>'handedOverAt' is not null and old.data->>'handedOverAt' is null then
  update commerce_orders set status='shipped' where id=oid and status='paid';
 end if;
 if new.data->>'confirmedAt' is not null and old.data->>'confirmedAt' is null then
  update commerce_orders set status='delivered' where id=oid and status in ('paid','shipped');
  update commerce_payments set buyer_confirmed_at=coalesce(buyer_confirmed_at,now()),picked_up_at=coalesce(picked_up_at,now()) where order_id=oid;
 end if;
 if ds_new is not null and ds_old is null then
  update commerce_payments set disputed=true where order_id=oid;
 end if;
 if ds_new='refunded' and ds_old is distinct from 'refunded' then
  update commerce_payments set disputed=true,refund_requested_at=coalesce(refund_requested_at,now()) where order_id=oid and status='paid';
 end if;
 if ds_new='rejected' and ds_old is distinct from 'rejected' then
  update commerce_payments set disputed=false where order_id=oid and refund_requested_at is null;
 end if;
 return new;
end $$;
drop trigger if exists commerce_delivery_sync on public.loop_deliveries;
create trigger commerce_delivery_sync before update on public.loop_deliveries for each row execute function public.commerce_delivery_sync();

-- Bez potvrde kupca: paket se smatra dostavljenim 5 dana nakon predaje
-- (nema praćenja kurira), zatim teče rok od 48 h za prijavu problema.
create or replace function public.commerce_auto_delivered() returns integer
language plpgsql security definer set search_path=public as $$ declare r record; n integer:=0; begin
 for r in select substr(d.id,17)::uuid oid from loop_deliveries d
   where d.id like 'del-stripe-sale-%' and d.data->>'handedOverAt' is not null and d.data->>'confirmedAt' is null
    and d.data->'dispute' is null and (d.data->>'handedOverAt')::timestamptz<now()-interval '5 days' loop
  update commerce_payments set picked_up_at=now() where order_id=r.oid and status='paid' and picked_up_at is null and not disputed;
  if found then n:=n+1; end if;
 end loop;
 return n;
end $$;
revoke all on function public.commerce_auto_delivered() from public,anon,authenticated;
grant execute on function public.commerce_auto_delivered() to service_role;

-- 7. Kao na Vintedu: kad je uplata kupca stigla, a prodavač još nema potvrđen
--    račun za isplatu, dobiva obavijest da je novac čeka i da potvrdu dovrši.
alter table public.commerce_payments add column if not exists payout_notice_at timestamptz;
create or replace function public.commerce_payout_notice() returns trigger
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; ok boolean; begin
 if new.status<>'paid' or old.status='paid' or new.payout_notice_at is not null then return new; end if;
 select * into o from commerce_orders where id=new.order_id;
 select coalesce(transfers_active,false) into ok from commerce_sellers where user_id=o.seller_id;
 if new.destination_account is null and not coalesce(ok,false) then
  perform srv_notify(o.seller_id::text,'payoutSetup',jsonb_build_array(coalesce(o.source_snapshot->>'name',''),new.seller_cents/100.0),o.id::text);
  new.payout_notice_at:=now();
 end if;
 return new;
end $$;
drop trigger if exists commerce_payout_notice on public.commerce_payments;
create trigger commerce_payout_notice before update on public.commerce_payments for each row execute function public.commerce_payout_notice();
grant execute on function public.srv_notify(text,text,jsonb,text) to service_role;

-- Postojeće zatvorene aukcije (ako ih ima aktivnih) nastavljaju kao klasične.
update public.loop_auctions set data=data||jsonb_build_object('kind','classic'),updated_at=now()
 where data->>'kind'='sealed' and data->>'status'='active';

do $$ declare sig text; begin
 foreach sig in array array['auction_create_order(text,jsonb,uuid,bigint)','commerce_order_fee_cents(public.commerce_orders)',
  'commerce_expire_order(uuid)','commerce_expire_orders(interval)','commerce_stuck_orders(interval)','auction_payment_due(uuid)',
  'commerce_claim_release(uuid)','commerce_fulfill_device(uuid)'] loop
  execute 'revoke all on function public.'||sig||' from public,anon,authenticated';
  execute 'grant execute on function public.'||sig||' to service_role';
 end loop;
end $$;
revoke all on function public.auction_settle(text) from public,anon;
grant execute on function public.auction_settle(text) to authenticated,service_role;
revoke all on function public.auction_take_dutch(text,numeric) from public,anon;
grant execute on function public.auction_take_dutch(text,numeric) to authenticated;
commit;

-- Rokovi: istek neplaćenih narudžbi svake minute (zaključivanje aukcija je u
-- prethodnoj migraciji, automatska naplata u sql/auction_charge_schedule.sql).
select cron.unschedule(jobid) from cron.job where jobname='subhasto-order-expiry';
select cron.schedule('subhasto-order-expiry','* * * * *','select public.commerce_expire_orders()');
select cron.unschedule(jobid) from cron.job where jobname='subhasto-auto-delivered';
select cron.schedule('subhasto-auto-delivered','17 * * * *','select public.commerce_auto_delivered()');
