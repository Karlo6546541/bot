begin;
create table public.commerce_delivery_locations (
 id text primary key,
 provider text not null check(provider='boxnow'),
 provider_id text not null,
 name text not null,
 address text not null,
 postal_code text not null,
 city text not null,
 country_code text not null check(country_code~'^[A-Z]{2}$'),
 latitude double precision check(latitude between -90 and 90),
 longitude double precision check(longitude between -180 and 180),
 active boolean not null default true,
 is_demo boolean not null default false,
 source_url text not null,
 updated_at timestamptz not null default now(),
 unique(provider,country_code,provider_id)
);
alter table public.commerce_delivery_locations enable row level security;
revoke all on public.commerce_delivery_locations from public,anon,authenticated;
grant select on public.commerce_delivery_locations to anon,authenticated;
grant all on public.commerce_delivery_locations to service_role;
create policy delivery_locations_read on public.commerce_delivery_locations for select to anon,authenticated using(active);
create index delivery_locations_country_postal on public.commerce_delivery_locations(country_code,postal_code) where active;

create function public.commerce_search_lockers(p_address text default '',p_country text default 'HR',p_limit integer default 30)
returns setof public.commerce_delivery_locations language sql stable security invoker set search_path=public as $$
 with q as (
  select translate(lower(left(coalesce(p_address,''),200)),'čćđšž','ccdsz') as text,
    substring(coalesce(p_address,'') from '\m[0-9]{4,6}\M') as postal
 ), locations as (
  select l.*,translate(lower(l.name||' '||l.address||' '||l.postal_code||' '||l.city),'čćđšž','ccdsz') as searchable,
   translate(lower(l.city),'čćđšž','ccdsz') as city_search from commerce_delivery_locations l
  where l.active and l.country_code=upper(p_country)
 )
 select l.id,l.provider,l.provider_id,l.name,l.address,l.postal_code,l.city,l.country_code,l.latitude,l.longitude,l.active,l.is_demo,l.source_url,l.updated_at
 from locations l cross join q
 where q.text='' or exists(select 1 from regexp_split_to_table(q.text,'[^[:alnum:]]+') token where length(token)>=3 and position(token in l.searchable)>0)
 order by (case when l.postal_code=q.postal then 200 else 0 end+
  case when position(l.city_search in q.text)>0 then 100 else 0 end+
  (select count(*)::int from regexp_split_to_table(q.text,'[^[:alnum:]]+') token where length(token)>=3 and position(token in l.searchable)>0)) desc,l.city,l.name,l.id
 limit greatest(1,least(coalesce(p_limit,30),50));
$$;
revoke all on function public.commerce_search_lockers(text,text,integer) from public;
grant execute on function public.commerce_search_lockers(text,text,integer) to anon,authenticated,service_role;

create or replace function public.commerce_choose_shipping(p_order uuid,p_method text,p_destination jsonb) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; l commerce_delivery_locations; destination jsonb; begin
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
 insert into commerce_shipments(order_id,method,destination) values(p_order,p_method,destination)
 on conflict(order_id) do update set method=excluded.method,destination=excluded.destination,updated_at=now();
end $$;
commit;
