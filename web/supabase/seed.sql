-- Monetization config (defaults mirror src/config/monetization.ts).
-- Demo users/series/images are created by `npm run seed` (scripts/seed.ts).
insert into public.pricing_plans (kind, code, name, price_cents, currency, coins, sort) values
  ('subscription', 'monthly', 'Mjesečna pretplata', 499, 'EUR', null, 0),
  ('coin_pack', 'coins_50', '50 novčića', 499, 'EUR', 50, 1),
  ('coin_pack', 'coins_120', '120 novčića', 999, 'EUR', 120, 2),
  ('coin_pack', 'coins_300', '300 novčića', 1999, 'EUR', 300, 3)
on conflict (code) do nothing;

insert into public.platform_settings (key, value) values
  ('creator_share_pct', '65'),
  ('coin_value_cents', '10'),
  ('default_coin_price', '5'),
  ('default_free_chapters', '3')
on conflict (key) do nothing;
