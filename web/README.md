# Kadar: digital comics platform (MVP)

A web platform for reading digital comics by Croatian and regional creators, with a monthly subscription and per-chapter unlocks paid in coins.

- **Stack:** Next.js 15 (App Router), TypeScript, Tailwind 4, Supabase (Postgres, Auth, Storage, RLS), installable PWA.
- **UI language:** Croatian. All strings live in `src/lib/i18n/messages/hr.ts`, and adding a language means adding one file (see `src/lib/i18n/index.ts`).
- **Payments:** a mock provider is the default and needs no keys. Stripe is fully implemented but only loads when `PAYMENT_PROVIDER=stripe`.

---

## 1. Local setup

Requirements: Node 20+, Docker (for local Supabase).

```bash
cd web
npm install
npx supabase start            # starts local Postgres/Auth/Storage (Docker)
npx supabase status           # prints the API URL, anon key and service_role key
cp .env.example .env.local    # paste NEXT_PUBLIC_SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY
npx supabase db reset         # applies migrations + supabase/seed.sql (prices, settings)
npm run seed                  # demo users, 3 series, chapters, images
npm run dev                   # http://localhost:3000
```

### Demo accounts (password for all: `lozinka123`)

| E-mail                   | Role                                      |
|--------------------------|-------------------------------------------|
| `admin@kadar.test`       | admin                                     |
| `ana@kadar.test`         | creator ("Sjene nad Gornjim gradom", "Orbita Velebit") |
| `marko@kadar.test`       | creator ("Galeb i more")                  |
| `citatelj@kadar.test`    | reader with 20 coins                      |
| `pretplatnik@kadar.test` | reader with an active subscription        |

The seed includes a free chapter, locked chapters, an early-access chapter and a scheduled chapter (publishes in 5 days) so every access rule can be tried out.

### Hosted Supabase

1. Create a project and run the migrations with `npx supabase link --project-ref <ref>` and then `npx supabase db push`.
2. Run `supabase/seed.sql` in the SQL editor (prices and settings).
3. Optionally run `npm run seed` with the project's URL and service key in `.env.local`.
4. In Auth → URL configuration, set the Site URL to your domain.
5. Make your account an admin:
   ```sql
   update profiles set role = 'admin' where id = (select id from auth.users where email = 'you@example.com');
   ```

### Tests

```bash
npm test          # unit: access rules, payment service, mock provider, Stripe webhooks (no network, no DB)
npm run test:db   # integration: RLS / storage / SQL functions against local Supabase (after npm run seed)
npm run typecheck
npm run build
```

---

## 2. Project structure

```
web/
  supabase/migrations/       schema, RLS, SQL functions, storage buckets
  supabase/seed.sql          prices + platform settings
  supabase/seed-assets/      placeholder images for the demo
  scripts/seed.ts            demo users and content
  src/config/monetization.ts monetization defaults (prices, 65/35, coin value, genres)
  src/lib/access/            canReadChapter() — the single access rule + server loader
  src/lib/payments/
    types.ts                 PaymentProvider interface + repository port
    service.ts               ALL payment business logic (shared by both providers)
    supabaseRepository.ts    persistence (service role, atomic SQL functions)
    mock/provider.ts         MockPaymentProvider
    stripe/provider.ts       StripePaymentProvider (SDK loaded lazily)
    index.ts                 picks the provider from PAYMENT_PROVIDER
  src/lib/i18n/              t() helper, Croatian dictionary, plural forms
  src/app/                   pages (browse, series, read, library, pricing, account,
                             creator/*, admin/*, checkout/*) and API routes
  tests/unit, tests/db
```

### Access model

A reader may open a chapter if it is **free**, **OR** they have an **active subscription**, **OR** they **unlocked it with coins**.

- **Free** means one of these: `access = free`; the chapter is among the first N chapters (N set per series); or it is an early-access chapter whose window has ended.
- Unreleased chapters (drafts, scheduled), drafts of series, and series hidden by an admin are unavailable to everyone except the owner and admins.
- The rule lives in `src/lib/access/canReadChapter.ts`. The SQL function `can_user_read_chapter` mirrors it for RLS, and a DB test checks that the two agree for every seeded user × chapter.

### Content protection

- Page images sit in the **private** `pages` bucket. A browser never gets direct access, not even for free chapters.
- The server checks access and then issues **signed URLs** that expire after `SIGNED_URL_TTL_SECONDS` (default 300 s). The reader requests fresh URLs automatically when they expire (`/api/chapters/[id]/pages`).
- RLS is on for every table. Clients can't write money tables (column grants and policies), and the payment SQL functions can only be executed by the service role.
- Rate limiting is an in-memory token bucket in `src/middleware.ts`. For multiple instances, swap it for Redis/Upstash.

### Money

- **Coin unlock:** the creator gets `price × coin_value_cents`, split by `creator_share_pct` (default 65%, overridable per creator in `creators.revenue_share_pct`).
- **Subscription:** each payment is recorded in `payments`. *Admin → Postavke prihoda → Pretplatnički fond* splits the creator share of a month's subscription revenue between series, in proportion to subscriber reads (`chapter_reads`). This runs once per month (idempotent). Run it **after** the month ends, because later payments for an already-distributed month are not redistributed.
- Payouts (Stripe Connect) are out of scope. For now, earnings are only recorded (`creator_earnings`, CSV export for creators).

---

## 3. Mock payment mode (default)

`PAYMENT_PROVIDER=mock` makes no external calls, and Stripe variables are not needed.

| Action | Where | Result (same records as a real payment) |
|---|---|---|
| Subscribe / buy coins | `/pricing` takes you to `/checkout/mock` | "Simuliraj uspješno plaćanje" writes `payments` + `subscriptions` / `coin_balances` + `coin_transactions`. "Simuliraj neuspjeh" writes nothing. |
| Cancel subscription | `/account` | `cancel_at_period_end = true`; access continues until the period ends |
| Subscription expires / renews | `/account` → "Testni alati (mock)" | `status = expired` (access stops immediately) / new period + new payment |
| Grant coins or a subscription to any user | `/admin/test-tools` (admin only, mock only) | `coin_transactions(admin_grant)` / mock subscription |

Clicking "success" twice on the same session does not charge twice, because the event is idempotent through `processed_payment_events`.

---

## 4. Switching to Stripe

The business logic (`src/lib/payments/service.ts`) does not change. Only the provider that translates Stripe events changes.

### Steps (test mode)

1. **Create products and prices** in the Stripe Dashboard (test mode) or with the CLI:
   ```bash
   stripe products create --name="Kadar mjesečna pretplata"
   stripe prices create --product=<prod_id> --unit-amount=499 --currency=eur -d "recurring[interval]=month"
   stripe products create --name="50 novčića"
   stripe prices create --product=<prod_id> --unit-amount=499 --currency=eur
   # repeat for 120 (999) and 300 (1999) coins
   ```
   Prices in Stripe must match `pricing_plans` (Admin → Postavke prihoda → Cjenik).
2. **Turn on the Customer Portal:** Dashboard → Settings → Billing → Customer portal (allow cancellation).
3. **Set environment variables** in `.env.local`:
   ```bash
   PAYMENT_PROVIDER=stripe
   STRIPE_SECRET_KEY=sk_test_...
   STRIPE_PRICE_ID_SUBSCRIPTION=price_...
   STRIPE_PRICE_ID_COINS_50=price_...
   STRIPE_PRICE_ID_COINS_120=price_...
   STRIPE_PRICE_ID_COINS_300=price_...
   ```
   Alternatively, enter the price IDs in Admin → Cjenik (`pricing_plans.stripe_price_id`). The env variables take precedence.
4. **Forward webhooks locally:**
   ```bash
   stripe login
   stripe listen --forward-to localhost:3000/api/webhooks/stripe \
     --events checkout.session.completed,checkout.session.async_payment_succeeded,invoice.paid,invoice.payment_failed,customer.subscription.created,customer.subscription.updated,customer.subscription.deleted
   ```
   Copy the printed `whsec_...` into `STRIPE_WEBHOOK_SECRET`.
5. **Restart** with `npm run dev`. The yellow "Testni način plaćanja" banner disappears and `/admin/test-tools` returns 404.
6. **Production:** in the Dashboard, add an endpoint at `https://<domain>/api/webhooks/stripe` with the same events, and use live keys and live price IDs.

### Verification checklist

- [ ] `/pricing` → "Pretplati se" opens Stripe Checkout. Pay with `4242 4242 4242 4242`. `stripe listen` shows `invoice.paid` → 200, `/account` shows "Aktivna do …", and a locked chapter opens.
- [ ] Buy a coin pack: `checkout.session.completed` → 200, and the balance in the header grows by the pack amount.
- [ ] Unlock a chapter with coins: the balance drops, and the creator's `/creator/earnings` shows a row under "Otključavanja".
- [ ] `stripe events resend <evt_id>` for the same event: the response is `"status":"duplicate"`, and the balance/payments don't change.
- [ ] A request with a wrong signature (`curl -X POST localhost:3000/api/webhooks/stripe -d '{}'`) returns 400.
- [ ] `/account` → "Upravljaj plaćanjem" opens the Stripe Customer Portal. Cancel there: `customer.subscription.updated` → "Otkazana — vrijedi do …".
- [ ] `stripe subscriptions cancel <sub_id>` → `customer.subscription.deleted` → access to locked chapters stops.
- [ ] Card `4000 0000 0000 0341` (fails on renewal) → `invoice.payment_failed` → status "Plaćanje nije uspjelo".
- [ ] In the Supabase table `processed_payment_events`, every Stripe event appears exactly once.

---

## 5. Notes and known MVP limitations

- `PAYMENT_PROVIDER=mock` is meant for development and demos. Don't use it in production with real users.
- The rate limiter and the reader's signed-URL refresh are per instance. Use a shared store when scaling.
- Creators upload images straight to Storage, after client-side downscaling (max 1200 px) and WebP conversion. There is no server-side image processing.
- Email notifications, comments and recommendations are out of scope for the MVP.
