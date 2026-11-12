-- Supabase migration; additive, independent of the legacy loop_* demo tables.
begin;
create table public.live_rooms (
 id uuid primary key default gen_random_uuid(), host_id uuid not null references auth.users(id),
 title text not null check(length(title) between 1 and 120), category text not null,
 status text not null default 'scheduled' check(status in ('scheduled','live','ended')),
 created_at timestamptz not null default now()
);
create table public.live_moderation (
 room_id uuid references public.live_rooms on delete cascade, user_id uuid references auth.users,
 muted boolean not null default false, banned boolean not null default false,
 primary key(room_id,user_id)
);
create table public.live_messages (
 id bigint generated always as identity primary key, room_id uuid not null references public.live_rooms on delete cascade,
 sender_id uuid not null references auth.users, request_id uuid not null,
 body text not null check(length(body) between 1 and 500), created_at timestamptz not null default clock_timestamp(),
 deleted boolean not null default false, unique(sender_id,request_id)
);
create index on public.live_messages(room_id,id desc);
create table public.live_lots (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.live_rooms,
 title text not null check(length(title) between 1 and 160),
 status text not null default 'queued' check(status in ('queued','running','sold','unsold')),
 start_cents bigint not null check(start_cents between 1 and 100000000),
 increment_cents bigint not null default 100 check(increment_cents between 1 and 1000000),
 price_cents bigint, winner_id uuid references auth.users, ends_at timestamptz,
 version bigint not null default 0
);
create unique index one_running_lot_per_room on public.live_lots(room_id) where status='running';
create table public.live_bids (
 id bigint generated always as identity primary key, lot_id uuid not null references public.live_lots,
 bidder_id uuid not null references auth.users, amount_cents bigint not null,
 request_id uuid not null, created_at timestamptz not null default clock_timestamp(), unique(bidder_id,request_id)
);
create index on public.live_bids(lot_id,id desc);
-- Auction award is NOT a payment or a completed sale.
create table public.live_awards (
 lot_id uuid primary key references public.live_lots, buyer_id uuid not null references auth.users,
 amount_cents bigint not null, status text not null default 'awaiting_checkout'
 check(status in ('awaiting_checkout','paid','cancelled')), created_at timestamptz not null default now()
);
create function public.live_can_join(p_room uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from live_rooms where id=p_room)
 and not exists(select 1 from live_moderation where room_id=p_room and user_id=auth.uid() and banned)
$$;
create function public.live_is_host(p_room uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from live_rooms where id=p_room and host_id=auth.uid())
$$;
-- No browser is allowed to directly write authoritative tables.
do $$ declare t text; begin
 foreach t in array array['live_rooms','live_moderation','live_messages','live_lots','live_bids','live_awards'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
grant select on public.live_rooms, public.live_lots, public.live_messages to anon;
create policy rooms_read on public.live_rooms for select to anon, authenticated using(public.live_can_join(id));
create policy lots_read on public.live_lots for select to anon, authenticated using(public.live_can_join(room_id));
create policy chat_read on public.live_messages for select to anon, authenticated using(public.live_can_join(room_id));
create policy moderation_read on public.live_moderation for select to authenticated using(user_id=auth.uid() or public.live_is_host(room_id));
create policy bids_read on public.live_bids for select to authenticated using(exists(select 1 from public.live_lots where id=lot_id and public.live_can_join(room_id)));
create policy awards_read on public.live_awards for select to authenticated using(buyer_id=auth.uid() or exists(select 1 from public.live_lots where id=lot_id and public.live_is_host(room_id)));
create function public.live_create_room(p_title text,p_category text) returns public.live_rooms
language plpgsql security definer set search_path=public as $$ declare r live_rooms; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 insert into live_rooms(host_id,title,category) values(auth.uid(),trim(p_title),p_category) returning * into r; return r;
end $$;
create function public.live_set_status(p_room uuid,p_status text) returns void
language plpgsql security definer set search_path=public as $$ begin
 if not live_is_host(p_room) then raise exception 'HOST_ONLY'; end if;
 -- Serialize lifecycle with bidding/finalization.
 perform 1 from live_rooms where id=p_room for update;
 if p_status not in ('live','ended') then raise exception 'INVALID_STATUS'; end if;
 if exists(select 1 from live_rooms where id=p_room and status='ended') then raise exception 'ROOM_ENDED'; end if;
 if p_status='ended' and exists(select 1 from live_lots where room_id=p_room and status='running') then raise exception 'LOT_RUNNING'; end if;
 update live_rooms set status=p_status where id=p_room;
end $$;
create function public.live_add_lot(p_room uuid,p_title text,p_start bigint,p_increment bigint) returns public.live_lots
language plpgsql security definer set search_path=public as $$ declare r live_lots; begin
 if not live_is_host(p_room) then raise exception 'HOST_ONLY'; end if;
 insert into live_lots(room_id,title,start_cents,increment_cents) values(p_room,p_title,p_start,p_increment) returning * into r; return r;
end $$;
create function public.live_start_lot(p_lot uuid,p_seconds integer) returns public.live_lots
language plpgsql security definer set search_path=public as $$ declare r live_lots; rid uuid; begin
 select room_id into rid from live_lots where id=p_lot;
 if not live_is_host(rid) then raise exception 'HOST_ONLY'; end if;
 perform 1 from live_rooms where id=rid and status='live' for update;
 if not found then raise exception 'ROOM_NOT_LIVE'; end if;
 if p_seconds not between 5 and 600 then raise exception 'INVALID_DURATION'; end if;
 update live_lots set status='running',ends_at=clock_timestamp()+make_interval(secs=>p_seconds),version=version+1
 where id=p_lot and status='queued' returning * into r;
 if not found then raise exception 'LOT_NOT_QUEUED'; end if; return r;
end $$;
create function public.live_send_message(p_room uuid,p_body text,p_request uuid) returns public.live_messages
language plpgsql security definer set search_path=public as $$ declare r live_messages; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if not live_can_join(p_room) then raise exception 'ACCESS_DENIED'; end if;
 -- Serialize per user, across tabs, to enforce rate limiting and retries.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into r from live_messages where sender_id=auth.uid() and request_id=p_request;
 if found then
 if r.room_id<>p_room then raise exception 'REQUEST_CONFLICT'; end if; return r; end if;
 if not exists(select 1 from live_rooms where id=p_room and status='live') then raise exception 'ROOM_NOT_LIVE'; end if;
 if exists(select 1 from live_moderation where room_id=p_room and user_id=auth.uid() and muted) then raise exception 'MUTED'; end if;
 if exists(select 1 from live_messages where sender_id=auth.uid() and created_at>clock_timestamp()-interval '1 second') then raise exception 'RATE_LIMIT'; end if;
 insert into live_messages(room_id,sender_id,request_id,body) values(p_room,auth.uid(),p_request,trim(p_body)) returning * into r; return r;
end $$;
create function public.live_place_bid(p_lot uuid,p_amount bigint,p_request uuid) returns public.live_bids
language plpgsql security definer set search_path=public as $$ declare l live_lots; b live_bids; rid uuid; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into b from live_bids where bidder_id=auth.uid() and request_id=p_request;
 if found then
 if b.lot_id<>p_lot or b.amount_cents<>p_amount then raise exception 'REQUEST_CONFLICT'; end if; return b; end if;
 select room_id into rid from live_lots where id=p_lot;
 perform 1 from live_rooms where id=rid and status='live' for update;
 if not found or not live_can_join(rid) or live_is_host(rid) then raise exception 'BID_FORBIDDEN'; end if;
 select * into l from live_lots where id=p_lot for update;
 if l.status<>'running' or l.ends_at<=clock_timestamp() then raise exception 'LOT_CLOSED'; end if;
 if p_amount<coalesce(l.price_cents+l.increment_cents,l.start_cents) or p_amount>100000000 then raise exception 'INVALID_AMOUNT'; end if;
 insert into live_bids(lot_id,bidder_id,amount_cents,request_id) values(p_lot,auth.uid(),p_amount,p_request) returning * into b;
 update live_lots set price_cents=p_amount,winner_id=auth.uid(),
 ends_at=greatest(ends_at,clock_timestamp()+interval '5 seconds'),version=version+1 where id=p_lot;
 return b;
end $$;
create function public.live_finish_lot(p_lot uuid) returns public.live_lots
language plpgsql security definer set search_path=public as $$ declare l live_lots; rid uuid; begin
 select room_id into rid from live_lots where id=p_lot;
 if auth.uid() is null or not live_can_join(rid) then raise exception 'ACCESS_DENIED'; end if;
 perform 1 from live_rooms where id=rid for update;
 select * into l from live_lots where id=p_lot for update;
 if l.status in ('sold','unsold') then return l; end if;
 if l.status<>'running' or l.ends_at>clock_timestamp() then raise exception 'LOT_NOT_ENDED'; end if;
 update live_lots set status=case when winner_id is null then 'unsold' else 'sold' end,version=version+1 where id=p_lot returning * into l;
 if l.winner_id is not null then insert into live_awards(lot_id,buyer_id,amount_cents) values(l.id,l.winner_id,l.price_cents) on conflict do nothing; end if;
 return l;
end $$;
create function public.live_moderate(p_room uuid,p_user uuid,p_muted boolean,p_banned boolean) returns void
language plpgsql security definer set search_path=public as $$ begin
 if not live_is_host(p_room) or p_user=auth.uid() then raise exception 'HOST_ONLY'; end if;
 insert into live_moderation values(p_room,p_user,p_muted,p_banned) on conflict(room_id,user_id) do update set muted=excluded.muted,banned=excluded.banned;
end $$;
create function public.live_delete_message(p_id bigint) returns void
language plpgsql security definer set search_path=public as $$ begin
 update live_messages set body='[removed]',deleted=true where id=p_id and (sender_id=auth.uid() or live_is_host(room_id));
 if not found then raise exception 'ACCESS_DENIED'; end if;
end $$;
-- Explicit grants: SECURITY DEFINER RPCs are never callable by anonymous clients.
do $$ declare f record; begin
 for f in select oid::regprocedure as sig from pg_proc where pronamespace='public'::regnamespace and proname like 'live\_%' escape '\' loop
 execute format('revoke all on function %s from public,anon',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
do $$ declare t text; begin
 foreach t in array array['live_rooms','live_lots','live_messages','live_moderation','live_awards'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
 execute format('alter publication supabase_realtime add table public.%I',t); end if;
 end loop;
end $$;
grant execute on function public.live_can_join(uuid) to anon;
commit;
