begin;
alter table public.live_rooms add column cover_url text, add column starts_at timestamptz not null default now(), add column lot_seconds integer not null default 30 check(lot_seconds in (5,10,15,20,30,45,60)), add column video_enabled boolean not null default true, add column creation_request uuid;
create unique index live_room_creation_retry on public.live_rooms(host_id,creation_request) where creation_request is not null;
alter table public.live_lots add column position integer not null default 0, add column image_url text, add column source_device_id text;
create function public.live_prepare_room(p_title text,p_category text,p_cover text,p_starts timestamptz,p_seconds integer,p_video boolean,p_lots jsonb,p_request uuid) returns public.live_rooms
language plpgsql security definer set search_path=public as $$
declare r live_rooms; item jsonb; n integer:=0; cents bigint; source_id text;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_request is null then raise exception 'REQUEST_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into r from live_rooms where host_id=auth.uid() and creation_request=p_request;
 if found then return r; end if;
 if length(trim(p_title)) not between 1 and 60 or p_title is null then raise exception 'INVALID_TITLE'; end if;
 if p_seconds not in (5,10,15,20,30,45,60) or p_seconds is null then raise exception 'INVALID_DURATION'; end if;
 if p_starts is not null and (p_starts<now()-interval '1 minute' or p_starts>now()+interval '7 days') then raise exception 'INVALID_SCHEDULE'; end if;
 if jsonb_typeof(p_lots) is distinct from 'array' or jsonb_array_length(p_lots)>200 then raise exception 'INVALID_LOTS'; end if;
 insert into live_rooms(host_id,title,category,status,cover_url,starts_at,lot_seconds,video_enabled,creation_request)
 values(auth.uid(),trim(p_title),p_category,case when p_starts is null then 'live' else 'scheduled' end,p_cover,coalesce(p_starts,now()),p_seconds,coalesce(p_video,true),p_request) returning * into r;
 for item in select value from jsonb_array_elements(p_lots) loop
  cents:=(item->>'start_cents')::bigint;
  if cents is null or cents<100 or cents>100000000 then raise exception 'INVALID_AMOUNT'; end if;
  source_id:=nullif(item->>'source_device_id','');
  if source_id is not null and not exists(select 1 from loop_devices where id=source_id and data->>'ownerId'=auth.uid()::text) then raise exception 'ITEM_NOT_OWNED'; end if;
  insert into live_lots(room_id,title,start_cents,increment_cents,position,image_url,source_device_id)
  values(r.id,item->>'title',cents,100,n,item->>'image_url',source_id);
  n:=n+1;
 end loop;
 return r;
end $$;
revoke all on function public.live_prepare_room(text,text,text,timestamptz,integer,boolean,jsonb,uuid) from public,anon;
grant execute on function public.live_prepare_room(text,text,text,timestamptz,integer,boolean,jsonb,uuid) to authenticated;
create or replace function public.live_add_lot(p_room uuid,p_title text,p_start bigint,p_increment bigint) returns public.live_lots
language plpgsql security definer set search_path=public as $$ declare r live_lots; begin
 if not live_is_host(p_room) then raise exception 'HOST_ONLY'; end if;
 perform 1 from live_rooms where id=p_room for update;
 insert into live_lots(room_id,title,start_cents,increment_cents,position) values(p_room,p_title,p_start,p_increment,coalesce((select max(position)+1 from live_lots where room_id=p_room),0)) returning * into r; return r;
end $$;
commit;
