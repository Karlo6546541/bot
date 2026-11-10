-- Admin helpers (service role only; callers must check the admin role first).
create or replace function public.admin_find_user_by_email(p_email text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1;
$$;

create or replace function public.admin_user_emails(p_ids uuid[])
returns table (id uuid, email text) language sql stable security definer set search_path = '' as $$
  select id, email::text from auth.users where id = any (p_ids);
$$;

revoke execute on function public.admin_find_user_by_email(text) from public, anon, authenticated;
revoke execute on function public.admin_user_emails(uuid[]) from public, anon, authenticated;
grant execute on function public.admin_find_user_by_email(text) to service_role;
grant execute on function public.admin_user_emails(uuid[]) to service_role;
