-- Aggregations for the subscription pool (avoid row limits of the REST API).
create or replace function public.sum_payments(p_period date, p_kind public.plan_kind)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce(sum(amount_cents), 0) from public.payments where period = p_period and kind = p_kind;
$$;

create or replace function public.subscription_reads_by_series(p_period date)
returns table (creator_id uuid, series_id uuid, reads bigint)
language sql stable security definer set search_path = '' as $$
  select creator_id, series_id, count(*) from public.chapter_reads
   where period = p_period and access_reason = 'subscription'
   group by creator_id, series_id order by series_id;
$$;

revoke execute on function public.sum_payments(date, public.plan_kind) from public, anon, authenticated;
revoke execute on function public.subscription_reads_by_series(date) from public, anon, authenticated;
grant execute on function public.sum_payments(date, public.plan_kind) to service_role;
grant execute on function public.subscription_reads_by_series(date) to service_role;
