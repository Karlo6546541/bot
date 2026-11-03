-- Subhasto order fixes. Apply after 20261102214615_subhasto_delivery_locations.sql.
--
-- 1. Orders awaiting payment expire, so a listing is not frozen forever.
-- 2. Shipping is priced on the server (it was always 0) and the paid order
--    creates the delivery record the app lists under "Dostave".
-- 3. The auction/live winner (and the seller of a refunded item) may take over
--    the item. The restrictive RLS policy allowed only the current owner, so
--    those writes were rejected and the error never surfaced.
-- 4. The platform commission matches the app: 5 % (kBuyNowRate), not 6 %.
-- 5. An accepted price offer (loop_bargains) is honoured by the server order.
--
-- Trust note for 3: auctions, bids and live events are client-written JSON in
-- the permissive loop_* tables, so the server verifies the award against them
-- but cannot make it tamper-proof. Full protection needs server-side settling.
begin;

-- 4. Commission -------------------------------------------------------------
create function public.commerce_fee_cents(p_item bigint) returns bigint
language sql immutable set search_path=pg_catalog as $$ select (p_item*5+50)/100 $$;

-- Share of the fee returned for a partial refund (rounded half up).
create function public.commerce_fee_share(p_fee bigint,p_item bigint,p_refunded bigint) returns bigint
language sql immutable set search_path=pg_catalog as $$
 select case when p_item<=0 then 0 else
  least(p_fee,(p_fee*least(greatest(p_refunded,0),p_item)*2+p_item)/(2*p_item)) end $$;

create or replace function public.commerce_begin_charge(p_order uuid) returns public.commerce_payments
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; p commerce_payments; fee bigint; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.status<>'awaiting_payment' then raise exception 'ORDER_NOT_PAYABLE'; end if;
 fee:=commerce_fee_cents(o.total_cents-o.shipping_cents);
 insert into commerce_payments(order_id,item_cents,fee_cents,seller_cents)
 values(o.id,o.total_cents-o.shipping_cents,fee,o.total_cents-o.shipping_cents-fee)
 on conflict(order_id) do nothing;
 select * into p from commerce_payments where order_id=p_order;
 return p;
end $$;

create or replace function public.commerce_record_refund(p_intent text,p_refunded bigint,p_disputed boolean default false) returns void
language plpgsql security definer set search_path=public as $$ declare p commerce_payments; begin
 select * into p from commerce_payments where intent_id=p_intent for update;
 if not found then return; end if;
 update commerce_payments set disputed=disputed or p_disputed,refunded_cents=greatest(refunded_cents,p_refunded),status=case when p_refunded>=(select total_cents from commerce_orders where id=p.order_id) then 'refunded' else status end where order_id=p.order_id;
 if p_refunded>0 then
  insert into commerce_platform_ledger(reference,kind,amount_cents,order_id)
  values('refund:'||p_intent||':'||p_refunded,'refund',
   -commerce_fee_share(p.fee_cents,p.item_cents,p_refunded)+commerce_fee_share(p.fee_cents,p.item_cents,p.refunded_cents),p.order_id) on conflict do nothing;
 end if;
 if p_refunded>=(select total_cents from commerce_orders where id=p.order_id) then update commerce_orders set status='refunded' where id=p.order_id; end if;
end $$;

-- 2. Shipping price (EUR cents): method base + parcel size surcharge ---------
-- Mirrors DeliveryMethod.cost and ParcelSize.extra in the app.
create function public.commerce_shipping_cents(p_method text,p_parcel text) returns bigint
language plpgsql immutable set search_path=pg_catalog as $$ declare base bigint; extra bigint; begin
 if p_method='pickup' then return 0; end if;
 extra:=case coalesce(p_parcel,'small') when 'medium' then 300 when 'large' then 900 when 'bulky' then 2900 else 0 end;
 if p_method='boxnow' then
  if p_parcel in ('large','bulky') then raise exception 'PARCEL_TOO_LARGE'; end if;
  base:=300;
 elsif p_method='courier' then base:=600;
 else raise exception 'INVALID_SHIPPING_METHOD'; end if;
 return base+extra;
end $$;

create or replace function public.commerce_choose_shipping(p_order uuid,p_method text,p_destination jsonb) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; l commerce_delivery_locations; destination jsonb; cents bigint; begin
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
 -- The price is fixed once a charge has started; before that it follows the method.
 if o.status='awaiting_payment' and not exists(select 1 from commerce_payments where order_id=o.id) then
  update commerce_orders set shipping_cents=cents,total_cents=(o.total_cents-o.shipping_cents)+cents where id=o.id;
 end if;
 insert into commerce_shipments(order_id,method,destination) values(p_order,p_method,destination)
 on conflict(order_id) do update set method=excluded.method,destination=excluded.destination,updated_at=now();
end $$;

-- Paid order -> item handover + delivery record shown in the app ("Dostave").
create or replace function public.commerce_fulfill_device(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; d jsonb; bought text; tx jsonb; item bigint; fee bigint; s commerce_shipments; dest text; m text; begin
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
 -- The accepted offer is spent by this purchase.
 update loop_bargains set data=data||jsonb_build_object('status','used','updatedAt',now())
  where data->>'deviceId'=o.source_device and data->>'buyerId'=o.buyer_id::text and data->>'status'='accepted';
 item:=o.total_cents-o.shipping_cents; fee:=commerce_fee_cents(item);
 tx:=jsonb_build_object('deviceId',bought,'deviceName',trim(coalesce(d->>'name','')||' '||coalesce(d->>'model','')),'price',item/100.0,'fee',0,'amount',o.total_cents/100.0,'buyerId',o.buyer_id,'sellerId',o.seller_id,'buyerLabel','','sellerLabel','','createdAt',now(),'isAuction',false);
 insert into loop_transactions(id,data) values('stripe-buy-'||o.id,tx||jsonb_build_object('id','stripe-buy-'||o.id,'type','buy','userId',o.buyer_id));
 insert into loop_transactions(id,data) values('stripe-sale-'||o.id,tx||jsonb_build_object('id','stripe-sale-'||o.id,'type','sell','userId',o.seller_id,'fee',fee/100.0,'amount',(item-fee)/100.0));
 -- The id links the delivery to its sale (see DisputeService.saleFor in the app).
 select * into s from commerce_shipments where order_id=o.id;
 if d->>'file' is null and found then
  m:=case s.method when 'boxnow' then 'parcelLocker' else s.method end;
  dest:=case s.method when 'boxnow' then concat_ws(', ',s.destination->>'name',s.destination->>'address',s.destination->>'city')
   when 'courier' then s.destination->>'address' else null end;
  insert into loop_deliveries(id,data) values('del-stripe-sale-'||o.id,jsonb_build_object(
   'id','del-stripe-sale-'||o.id,'deviceId',bought,'deviceName',trim(coalesce(d->>'name','')||' '||coalesce(d->>'model','')),
   'buyerId',o.buyer_id,'sellerId',o.seller_id,'createdAt',now(),'startedAt',now(),'method',m,'destination',dest,
   'cost',o.shipping_cents/100.0,'fromAuction',false,'reviewed',false,
   'trackingNumber','SUBH-'||upper(substr(md5(o.id::text),1,8)),
   'dropOffPin',case when s.method='boxnow' then lpad((floor(random()*1000000))::int::text,6,'0') end,
   'pickupPin',case when s.method='boxnow' then lpad((floor(random()*1000000))::int::text,6,'0') end))
  on conflict(id) do nothing;
 end if;
end $$;

-- 1. Expiry of unpaid orders -------------------------------------------------
-- Cancels one order that is still awaiting payment and releases its stock.
create function public.commerce_expire_order(p_order uuid) returns boolean
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.status<>'awaiting_payment' then return false; end if;
 if exists(select 1 from commerce_checkout_sessions where order_id=o.id) then return false; end if;
 if exists(select 1 from commerce_payments where order_id=o.id and status in ('paid','refunded')) then return false; end if;
 update commerce_payments set status='failed' where order_id=o.id and status='pending';
 update commerce_orders set status='cancelled' where id=o.id;
 update commerce_products set stock=stock+o.quantity where id=o.product_id;
 update live_awards set status='cancelled' where lot_id=o.award_lot_id;
 return true;
end $$;

-- Orders that never reached Stripe (no PaymentIntent) and are older than p_idle.
create function public.commerce_expire_orders(p_idle interval default interval '30 minutes') returns integer
language plpgsql security definer set search_path=public as $$ declare r record; n integer:=0; begin
 for r in select id from commerce_orders ord where status='awaiting_payment' and created_at<now()-p_idle
   and not exists(select 1 from commerce_payments p where p.order_id=ord.id and p.intent_id is not null) loop
  if commerce_expire_order(r.id) then n:=n+1; end if;
 end loop;
 return n;
end $$;

-- Orders with a PaymentIntent that never succeeded; the Edge job asks Stripe first.
create function public.commerce_stuck_orders(p_idle interval default interval '2 hours') returns table(order_id uuid,intent_id text)
language sql stable security definer set search_path=public as $$
 select o.id,p.intent_id from commerce_orders o join commerce_payments p on p.order_id=o.id
 where o.status='awaiting_payment' and p.status='pending' and p.intent_id is not null and o.created_at<now()-p_idle
 order by o.created_at limit 20 $$;

-- 3. Item takeover by a verified auction/live winner or by the seller of a refund
create function public.commerce_award_verified(p_device text,p_buyer uuid) returns boolean
language plpgsql stable security definer set search_path=public as $$ declare t record; a jsonb; show text; idx integer; lastbid jsonb; begin
 if p_buyer is null or p_device is null then return false; end if;
 for t in select id,data from loop_transactions where data->>'deviceId'=p_device and data->>'buyerId'=p_buyer::text
   and data->>'type'='sell' and coalesce((data->>'isAuction')::boolean,false) and (id like 'auction-%' or id like 'live-%') loop
  if t.id like 'auction-%' then
   select data into a from loop_auctions where id=substr(t.id,9);
   if a is not null and a->>'deviceId'=p_device and a->>'sellerId'=t.data->>'sellerId' then
    lastbid:=a->'bids'->-1;
    if lastbid->>'userId'=p_buyer::text and (lastbid->>'amount')::numeric=(t.data->>'price')::numeric
     and ((a->>'endsAt')::timestamptz<=now() or (a->>'buyNowPrice' is not null and (lastbid->>'amount')::numeric>=(a->>'buyNowPrice')::numeric)) then return true; end if;
   end if;
  else
   show:=substring(t.id from '^live-(.*)-[0-9]+$'); idx:=substring(t.id from '^live-.*-([0-9]+)$')::integer;
   if show is not null and idx is not null
    and exists(select 1 from loop_live_shows s where s.id=show and s.data->>'hostId'=t.data->>'sellerId')
    and exists(select 1 from loop_live_events e where e.data->>'showId'=show and e.data->>'userId'=p_buyer::text and e.data->>'lot'=idx::text
      and (e.data->>'type'='enter' or (e.data->>'type' in ('bid','take') and (e.data->>'amount')::numeric>=(t.data->>'price')::numeric-0.005))) then return true; end if;
  end if;
 end loop;
 return false;
end $$;

-- The seller gets a refunded item back (the buyer returns it).
create function public.commerce_refund_return_ok(p_device text,p_seller text) returns boolean
language sql stable security definer set search_path=public as $$
 select p_seller is not null and exists(select 1 from loop_deliveries d where d.data->>'deviceId'=p_device
  and d.data->>'sellerId'=p_seller and d.data->'dispute'->>'status'='refunded') $$;

drop policy stripe_listing_update on public.loop_devices;
create policy stripe_listing_update on public.loop_devices as restrictive for update to authenticated
 using(data->>'ownerId'=auth.uid()::text or public.commerce_award_verified(id,auth.uid()) or public.commerce_refund_return_ok(id,auth.uid()::text))
 with check(data->>'ownerId'=auth.uid()::text or public.commerce_award_verified(id,auth.uid()) or public.commerce_refund_return_ok(id,data->>'ownerId'));

-- A non-owner may only take the item over or take one piece from the stock.
create function public.commerce_award_guard() returns trigger language plpgsql set search_path=public as $$
declare k text[]:=array['ownerId','listPrice','listedAt','quantity','discountPercent','discountUntil','priceLog','marketChecked']; begin
 if current_user in ('postgres','service_role','supabase_admin') or auth.uid() is null or old.data->>'ownerId'=auth.uid()::text then return new; end if;
 if (new.data-k) is distinct from (old.data-k) then raise exception 'AWARD_FIELDS'; end if;
 if new.data->>'ownerId'=auth.uid()::text then return new; end if;
 if new.data->>'ownerId'=old.data->>'ownerId' and (new.data->>'quantity')::integer=(old.data->>'quantity')::integer-1
  and (new.data->>'quantity')::integer>=1 then return new; end if;
 raise exception 'AWARD_FORBIDDEN';
end $$;
create trigger award_guard before update on public.loop_devices for each row execute function public.commerce_award_guard();

-- 5. Order price = listing price (with discount), or the accepted offer if lower ----
create or replace function public.commerce_device_cents(p_device text,p_data jsonb,p_buyer uuid) returns bigint
language plpgsql stable security definer set search_path=public as $$ declare cents bigint; b jsonb; agreed bigint; begin
 cents:=round((p_data->>'listPrice')::numeric*100);
 if coalesce((p_data->>'discountPercent')::integer,0)>0 and (p_data->>'discountUntil' is null or (p_data->>'discountUntil')::timestamptz>now()) then
  cents:=round(cents*(100-(p_data->>'discountPercent')::integer)/100.0);
 end if;
 select data into b from loop_bargains where data->>'deviceId'=p_device and data->>'buyerId'=p_buyer::text
  and data->>'status'='accepted' and (data->>'validUntil')::timestamptz>now()
  order by data->>'updatedAt' desc limit 1;
 if found then
  agreed:=round(coalesce((b->>'counterAmount')::numeric,(b->>'amount')::numeric)*100);
  if agreed>0 and agreed<cents then cents:=agreed; end if;
 end if;
 return cents;
end $$;

create or replace function public.commerce_reserve_device(p_device text,p_request uuid) returns public.commerce_orders
language plpgsql security definer set search_path=public as $$ declare d jsonb; o commerce_orders; cents bigint; available integer; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into o from commerce_orders where buyer_id=auth.uid() and request_id=p_request;
 if found then
  if o.source_device is distinct from p_device then raise exception 'REQUEST_CONFLICT'; end if; return o;
 end if;
 select data into d from loop_devices where id=p_device for update;
 if not found or d->>'ownerId' is null or d->>'ownerId'=auth.uid()::text or d->>'listPrice' is null then raise exception 'UNAVAILABLE'; end if;
 cents:=commerce_device_cents(p_device,d,auth.uid());
 if cents<50 or cents>10000000 then raise exception 'INVALID_AMOUNT'; end if;
 -- An interrupted purchase reopens the same order (re-priced while nothing is charged).
 select * into o from commerce_orders where buyer_id=auth.uid() and source_device=p_device and status='awaiting_payment' order by created_at desc limit 1;
 if found then
  if not exists(select 1 from commerce_payments where order_id=o.id) then
   update commerce_orders set total_cents=cents+o.shipping_cents where id=o.id returning * into o;
  end if;
  return o;
 end if;
 available:=coalesce((d->>'quantity')::integer,1);
 if d->>'file' is null and (select count(*) from commerce_orders where source_device=p_device and status='awaiting_payment')>=available then raise exception 'UNAVAILABLE'; end if;
 insert into commerce_orders(buyer_id,seller_id,quantity,total_cents,request_id,source_device,source_snapshot)
 values(auth.uid(),(d->>'ownerId')::uuid,1,cents,p_request,p_device,d) returning * into o;
 if d->>'file' is not null then insert into commerce_shipments(order_id,method,destination) values(o.id,'pickup','{}'); end if;
 return o;
end $$;
revoke all on function public.commerce_device_cents(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.commerce_device_cents(text,jsonb,uuid) to service_role;

do $$ declare sig text; begin
 foreach sig in array array['commerce_expire_order(uuid)','commerce_expire_orders(interval)','commerce_stuck_orders(interval)'] loop
  execute 'revoke all on function public.'||sig||' from public,anon,authenticated';
  execute 'grant execute on function public.'||sig||' to service_role';
 end loop;
 foreach sig in array array['commerce_award_verified(text,uuid)','commerce_refund_return_ok(text,text)'] loop
  execute 'revoke all on function public.'||sig||' from public,anon';
  execute 'grant execute on function public.'||sig||' to authenticated,service_role';
 end loop;
end $$;
commit;
