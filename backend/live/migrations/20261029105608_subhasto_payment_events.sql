begin;
-- Only the backend service role may retrieve the fixed integration allowlist.
create function public.subhasto_integration_secrets() returns jsonb
language sql stable security definer set search_path=pg_catalog as $$
 select coalesce(jsonb_object_agg(name,decrypted_secret),'{}'::jsonb)
 from vault.decrypted_secrets where name in (
 'STRIPE_RESTRICTED_KEY','STRIPE_SECRET_KEY','STRIPE_WEBHOOK_SECRET',
 'LIVEKIT_URL','LIVEKIT_API_KEY','LIVEKIT_API_SECRET')
$$;
revoke all on function public.subhasto_integration_secrets() from public,anon,authenticated;
grant execute on function public.subhasto_integration_secrets() to service_role;
alter table public.commerce_checkout_sessions add column failed boolean not null default false;
create function public.commerce_record_failure(p_event text,p_order uuid,p_session text) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if o.status<>'awaiting_payment' then return; end if;
 if not exists(select 1 from commerce_checkout_sessions where order_id=p_order and session_id=p_session) then raise exception 'SESSION_MISMATCH'; end if;
 if exists(select 1 from commerce_payment_events where provider_event_id=p_event) then
   if not exists(select 1 from commerce_payment_events where provider_event_id=p_event and order_id=p_order and event_type='failed') then raise exception 'EVENT_CONFLICT'; end if;
   return;
 end if;
 insert into commerce_payment_events values(p_event,p_order,'failed',now());
 update commerce_checkout_sessions set failed=true where order_id=p_order and session_id=p_session;
end $$;
revoke all on function public.commerce_record_failure(text,uuid,text) from public,anon,authenticated;
grant execute on function public.commerce_record_failure(text,uuid,text) to service_role;
create or replace function public.commerce_record_payment(p_event text,p_order uuid,p_amount bigint,p_currency text) returns void
language plpgsql security definer set search_path=public as $$ declare o commerce_orders; begin
 select * into o from commerce_orders where id=p_order for update;
 if not found or o.total_cents<>p_amount or o.currency<>p_currency then raise exception 'PAYMENT_MISMATCH'; end if;
 if exists(select 1 from commerce_payment_events where provider_event_id=p_event) then
 if not exists(select 1 from commerce_payment_events where provider_event_id=p_event and order_id=p_order) then raise exception 'EVENT_CONFLICT'; end if; return; end if;
 if o.status in ('paid','shipped','delivered') then
 insert into commerce_payment_events values(p_event,p_order,'paid',now()); return; end if;
 if o.status<>'awaiting_payment' then raise exception 'INVALID_PAYMENT_STATE'; end if;
 insert into commerce_payment_events values(p_event,p_order,'paid',now());
 update commerce_orders set status='paid' where id=p_order;
 update live_awards set status='paid' where lot_id=o.award_lot_id;
 insert into commerce_notifications(user_id,kind,order_id) values(o.buyer_id,'order_paid',o.id),(o.seller_id,'order_to_ship',o.id);
end $$;
-- Retention deletes auth users and must never be callable by public app clients.
revoke execute on function public.loop_purge_deleted() from public,anon,authenticated;
grant execute on function public.loop_purge_deleted() to service_role;
commit;
