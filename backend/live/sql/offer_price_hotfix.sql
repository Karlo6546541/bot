-- Hotfix: a server order uses the accepted price offer (loop_bargains) instead of the
-- listing price ("Cijena je promijenjena" at checkout). Safe to run before or after
-- 20261103000000_subhasto_order_fixes.sql (both use create or replace).
begin;
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
commit;
