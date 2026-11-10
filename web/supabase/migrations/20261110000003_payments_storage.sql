-- =============================================================================
-- Atomic money primitives (called ONLY by the server-side payment service with
-- the service role). Business rules (prices, revenue split) are computed in
-- TypeScript (src/lib/payments/service.ts); these functions only guarantee
-- atomicity and idempotency.
-- =============================================================================

-- Credit (or debit) coins. Idempotent per (type, provider_ref).
create or replace function public.apply_coin_credit(
  p_user uuid, p_amount int, p_type public.coin_tx_type,
  p_plan uuid default null, p_provider public.payment_provider default null,
  p_ref text default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_bal int;
begin
  if p_amount = 0 then raise exception 'amount must not be zero'; end if;
  if p_ref is not null and exists (
    select 1 from public.coin_transactions where type = p_type and provider_ref = p_ref
  ) then
    select balance into v_bal from public.coin_balances where user_id = p_user;
    return jsonb_build_object('status', 'duplicate', 'balance', coalesce(v_bal, 0));
  end if;

  insert into public.coin_balances (user_id, balance) values (p_user, p_amount)
  on conflict (user_id) do update
    set balance = public.coin_balances.balance + excluded.balance, updated_at = now()
  returning balance into v_bal;

  insert into public.coin_transactions (user_id, type, amount, balance_after, plan_id, provider, provider_ref, note)
  values (p_user, p_type, p_amount, v_bal, p_plan, p_provider, p_ref, p_note);

  return jsonb_build_object('status', 'ok', 'balance', v_bal);
end $$;

-- Spend coins on a chapter + credit creator earnings, all-or-nothing.
create or replace function public.apply_chapter_unlock(
  p_user uuid, p_chapter uuid, p_price int,
  p_creator uuid, p_series uuid,
  p_gross_cents int, p_creator_cents int, p_platform_cents int,
  p_share_pct numeric, p_period date
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_bal int;
begin
  if exists (select 1 from public.chapter_unlocks where user_id = p_user and chapter_id = p_chapter) then
    select balance into v_bal from public.coin_balances where user_id = p_user;
    return jsonb_build_object('status', 'already_unlocked', 'balance', coalesce(v_bal, 0));
  end if;

  select balance into v_bal from public.coin_balances where user_id = p_user for update;
  if v_bal is null or v_bal < p_price then
    return jsonb_build_object('status', 'insufficient_coins', 'balance', coalesce(v_bal, 0));
  end if;

  update public.coin_balances set balance = balance - p_price, updated_at = now()
   where user_id = p_user returning balance into v_bal;

  if p_price > 0 then
    insert into public.coin_transactions (user_id, type, amount, balance_after, chapter_id)
    values (p_user, 'unlock', -p_price, v_bal, p_chapter);
  end if;

  insert into public.chapter_unlocks (user_id, chapter_id, coins_spent) values (p_user, p_chapter, p_price);

  if p_gross_cents > 0 then
    insert into public.creator_earnings
      (creator_id, series_id, chapter_id, source, gross_cents, creator_cents, platform_cents, share_pct, period, ref)
    values
      (p_creator, p_series, p_chapter, 'coin_unlock', p_gross_cents, p_creator_cents, p_platform_cents,
       p_share_pct, p_period, 'unlock:' || p_user || ':' || p_chapter);
  end if;

  return jsonb_build_object('status', 'unlocked', 'balance', v_bal);
end $$;

-- Idempotency guard for webhook / simulated events. Returns true the first time.
create or replace function public.claim_payment_event(p_provider text, p_event_id text, p_type text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  insert into public.processed_payment_events (provider, event_id, type)
  values (p_provider, p_event_id, p_type)
  on conflict do nothing;
  return found;
end $$;

-- If handling failed after the claim, release it so the provider's retry works.
create or replace function public.release_payment_event(p_provider text, p_event_id text)
returns void language sql security definer set search_path = '' as $$
  delete from public.processed_payment_events where provider = p_provider and event_id = p_event_id;
$$;

revoke execute on function public.apply_coin_credit(uuid, int, public.coin_tx_type, uuid, public.payment_provider, text, text) from public, anon, authenticated;
revoke execute on function public.apply_chapter_unlock(uuid, uuid, int, uuid, uuid, int, int, int, numeric, date) from public, anon, authenticated;
revoke execute on function public.claim_payment_event(text, text, text) from public, anon, authenticated;
revoke execute on function public.release_payment_event(text, text) from public, anon, authenticated;
grant execute on function public.apply_coin_credit(uuid, int, public.coin_tx_type, uuid, public.payment_provider, text, text) to service_role;
grant execute on function public.apply_chapter_unlock(uuid, uuid, int, uuid, uuid, int, int, int, numeric, date) to service_role;
grant execute on function public.claim_payment_event(text, text, text) to service_role;
grant execute on function public.release_payment_event(text, text) to service_role;

-- =============================================================================
-- Storage
--   covers: public bucket, path "<series_id>/<file>"
--   pages:  PRIVATE bucket, path "<series_id>/<chapter_id>/<file>".
--           Readers never get direct access; the server checks access and
--           returns short-lived signed URLs.
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('covers', 'covers', true, 2097152, array['image/webp', 'image/jpeg', 'image/png']),
  ('pages', 'pages', false, 6291456, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy "covers: owner writes" on storage.objects for insert to authenticated
  with check (bucket_id = 'covers' and public.owns_series_path((storage.foldername(name))[1]));
create policy "covers: owner updates" on storage.objects for update to authenticated
  using (bucket_id = 'covers' and public.owns_series_path((storage.foldername(name))[1]));
create policy "covers: owner deletes" on storage.objects for delete to authenticated
  using (bucket_id = 'covers' and public.owns_series_path((storage.foldername(name))[1]));

create policy "pages: owner writes" on storage.objects for insert to authenticated
  with check (bucket_id = 'pages' and public.owns_series_path((storage.foldername(name))[1]));
create policy "pages: owner reads" on storage.objects for select to authenticated
  using (bucket_id = 'pages' and public.owns_series_path((storage.foldername(name))[1]));
create policy "pages: owner deletes" on storage.objects for delete to authenticated
  using (bucket_id = 'pages' and public.owns_series_path((storage.foldername(name))[1]));
