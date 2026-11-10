-- Monthly earnings per series and source. SECURITY INVOKER: RLS limits rows to
-- the caller's own earnings (admins see all, optionally filtered by creator).
create or replace function public.earnings_summary(p_creator uuid default null)
returns table (
  period date, creator_id uuid, series_id uuid, series_title text, source public.earning_source,
  items bigint, gross_cents bigint, creator_cents bigint, platform_cents bigint
)
language sql stable security invoker set search_path = '' as $$
  select e.period, e.creator_id, e.series_id, coalesce(s.title, '—'), e.source,
         count(*), sum(e.gross_cents), sum(e.creator_cents), sum(e.platform_cents)
    from public.creator_earnings e
    left join public.series s on s.id = e.series_id
   where p_creator is null or e.creator_id = p_creator
   group by e.period, e.creator_id, e.series_id, s.title, e.source
   order by e.period desc, s.title;
$$;
revoke execute on function public.earnings_summary(uuid) from public, anon;
grant execute on function public.earnings_summary(uuid) to authenticated, service_role;
