# Live commerce backend

This is an additive production backend foundation, not Whatnot's proprietary architecture.
The default Flutter UI uses the legacy `LiveService`. The opt-in online route uses the APIs below.
`LiveBackend` and `CommerceBackend` power the new CloudCommerceScreen. Activation
is pending deployment of the real services. Do not label the demo as production.

## Responsibilities

- Supabase Auth: verified user identity; never accept a client-supplied host/bidder ID.
- Postgres: live rooms, lots, durable chat, moderation, bid ledger, checkout awards.
- RPC transactions: lock the room and lot, validate server time/amount, extend the
  countdown by five seconds on late bids, and award at most once. EUR amounts are cents.
- Realtime: scoped change notifications. Resubscribe then refetch canonical state;
  paginate chat by ID (50 per page), deduplicate IDs, and preserve request UUIDs on retry.
- LiveKit SFU: host uploads a single stream; SFU distributes it to viewers. Chat and
  bids must not use transient LiveKit data messages as their source of truth.
- `live-token`: verifies Supabase JWT when supplied and room access, issues a five-minute room-scoped
  token. Only the database room host can publish. Keys remain in Edge Function secrets.

## Deployment

1. Create a Supabase project and a LiveKit Cloud project near the audience. Configure
   Supabase Auth allowed redirect URLs for `https://karlo6546541.github.io/bot/` and native
   deep links. Use real authenticated identities; do not copy demo user IDs into Auth.
2. Apply `migrations/001_live.sql` once with Supabase SQL Editor/migration tooling.
   It creates separate tables and does not modify or secure the older demo schema.
   Never run the permissive legacy schema as a production trading backend.
3. Copy `functions/live-token` into the Supabase project's functions directory and deploy
   with gateway JWT verification disabled for this one public viewer endpoint
   (`[functions.live-token] verify_jwt = false`). It verifies user tokens itself; guests
   receive subscribe-only media tokens and have SELECT-only database access. Set secrets `LIVEKIT_API_KEY`,
   `LIVEKIT_API_SECRET`, `LIVEKIT_URL` (`wss://…`) and `APP_ORIGIN`
   (`https://karlo6546541.github.io`). Supabase supplies its URL and anon key.
4. Build the app with public `SUPABASE_URL` and `SUPABASE_KEY`. Never embed a service-role
   key or LiveKit secret in Dart, GitHub Pages, source files or build-time public defines.
5. Integrate `lib/services/live_backend.dart` into the room UI and a LiveKit Flutter
   controller: connect with `videoToken`, host enables camera/microphone, viewer only
   subscribes. Disconnect and remove Realtime channels on room exit. On expired tokens,
   request a fresh token after authenticating again. Remove the P2P path for these rooms.
6. Route room create/start/end, chat and bids through RPCs. UI renders pending commands
   but only confirms success after server acknowledgment; never update the legacy Hive
   bid log in parallel. Use server `ends_at`, not device time, to decide auction validity.
7. Add a trusted scheduled finalizer for expired lots (including rooms with no connected
   clients), persistent outbox/worker for checkout, payment webhooks and stock reservation.
   `live_finish_lot` already finalizes safely when called by an authorized connected user;
   its repeated call returns the same award. An award is not a payment.
8. Add LiveKit moderation eviction to the trusted moderation workflow: DB ban blocks new
   tokens/chat/bids but cannot revoke an already connected SFU participant. Use server
   `removeParticipant` on ban/end. Short token TTL alone does not disconnect a participant.

## Rollout gates

Before real transactions: test two physical phones on different networks, reconnect and
background recovery, simultaneous bids against real Postgres, expiry without viewers,
room end/ban SFU eviction, recording consent, payment failures/refunds and monitoring.
Add admission rate limits and capacity alerts to the token endpoint. Monitor room count,
chat/bid latency, rejected requests, SFU egress and reconnects; choose an initial capacity
from a load test rather than claiming a viewer count.

There are no configured Supabase/LiveKit credentials in this workspace. No production
migration, account creation, video deployment or existing-user migration has been performed.

## Local database checks

`npm ci && npm test` in this directory runs the migration in embedded Postgres (PGlite).
Checks cover anonymous room/chat reads, guest write denial, direct-write denial, host ownership, bid increments, idempotency, mute/ban,
chat rate limit, RLS, server expiry, and one award. This is not a multi-session load test.

## Commerce migration (002)

Apply `002_commerce.sql` after `001_live.sql`. It adds product stock, reservations,
private buyer/seller orders, auction-award checkout, follows, favorites, shipping
selection, tracking, delivery confirmation and in-app notifications. Flutter API:
`CommerceBackend`. These tables are intentionally not mirrored to the legacy Hive
order store; UI migration must choose one authoritative backend for each order.

Lifecycle: reserve stock → select shipping → verified payment event → paid → seller
ships → buyer confirms delivery. Unpaid cancellation restores stock exactly once.
An unpaid reservation currently has no automatic TTL: deploy an expiry worker before
exposing public checkout, otherwise abandoned reservations can exhaust inventory.
Shipping selection stores a request, not a purchased BOX NOW label. Carrier API calls,
label generation, tracking webhooks and address validation remain separate work.

`commerce_record_payment` is executable only by `service_role` (trusted worker). It is
not a public webhook endpoint: the provider integration must verify signature, amount,
currency, merchant identity and replay protection before calling it. Never call it
from the app or use it to simulate real payments. Refunds, chargebacks, seller KYC,
connected-account payouts, reconciliation and tax reporting are not implemented here.
Payment rows are private; shipping destinations are visible only to order parties.

## Delivery status of the whole system

| Area | Implemented here | Still required before activation |
|---|---|---|
| Login | Existing Supabase Auth in deployed app | Exercise real user registration/reset/redirects |
| Live/video | Host-scoped LiveKit token function | LiveKit project, media controller, deployment and device test |
| Chat/moderation | Durable messages, guest reads, mute/ban, RLS | Wire existing UI, disconnect banned media participants |
| Auctions | Locked bids, expiry validation, idempotent award | Trusted scheduled settlement and load tests |
| Catalog/orders | Stock, reserve/cancel, award checkout RPC | Wire screens, reservation expiry and product media |
| Social | Authenticated follow/favorite RPC | Migrate existing profile/feed state |
| Notifications | Private order notifications | Realtime UI subscription and push provider |
| Shipping | Private shipping selection and tracking | BOX NOW/other carrier credentials and label APIs |
| Money | Trusted payment-event boundary | Payment provider, verified webhook, refunds and payouts |
| Trust/support | Existing app reports/legal UI | Staff roles, case queue, audits and retention policies |

No claim is made that all Whatnot functionality is implemented or that these migrations
have been applied to the user's project. This branch contains the tested backend core
and adapters. Real service credentials and deployment/integration are outstanding.

## Integrated online screens and Stripe test mode

The new `CloudCommerceScreen` now calls these APIs for room creation/start/end,
web SFU playback/host camera, live chat, moderation, bidding, auction checkout,
product publishing/reservation, private orders, shipping, tracking and delivery.
It is reachable from the top-right menu **Live i trgovina online** when built
with `--dart-define=CLOUD_COMMERCE_ENABLED=true`. In Pages builds set repository
variable `CLOUD_COMMERCE_ENABLED=true` after deploying services. The switch is OFF
by default so an unconfigured backend does not break existing accounts/orders.
Legacy records remain in the existing UI; no automatic data migration is performed.

Apply migrations **001, 002, 003** in order. Merge this directory's `config.toml`
function settings into the Supabase CLI project and deploy all five functions:
`live-token`, `live-control`, `stripe-connect`, `stripe-checkout`, `stripe-webhook`, including the
`_shared` folder. The functions authenticate users themselves; public viewer token
access and Stripe webhooks have gateway JWT verification disabled deliberately.

Set server-only Edge Function secrets in Supabase (never GitHub Pages):

- `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- `STRIPE_SECRET_KEY` (only `sk_test_…` is accepted)
- `STRIPE_WEBHOOK_SECRET` (`whsec_…`)
- `APP_ORIGIN=https://karlo6546541.github.io`
- `APP_URL=https://karlo6546541.github.io/bot/`

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` inside its Edge Function runtime.
Stripe dashboard test webhook URL:
`https://mwhrjrxytfdttjjdhdns.supabase.co/functions/v1/stripe-webhook`.
Subscribe to `checkout.session.completed`. The webhook validates the raw request
signature, test-mode flag, paid status, our recorded session/order association,
amount and currency. Retries are idempotent; the success redirect never marks paid.

Seller settings → **Postavi Stripe račun prodavatelja (test)** opens Stripe Express
onboarding. Ready sellers receive destination charges through hosted Checkout.
No real card data enters Flutter. The new online checkout is for test payments
only, with item price as the total; shipping fees, tax and platform commission
are not currently charged. Do not enable live keys by removing the guard without
implementing refund, chargeback and payout reconciliation.

The SFU player uses the official pinned LiveKit web SDK in `live-player.html`.
Camera/microphone start from a host gesture; guests get subscribe-only grants.
This media controller currently supports the web app; native Android/iOS show a
web-version hint. Native LiveKit SDK integration and on-device verification remain
outstanding. The legacy P2P media path is not silently replaced on native builds.

Checkout creates a durable payment lock before calling Stripe. Pending checkout
orders cannot be cancelled/restocked by the browser; recovery/expiry requires a
trusted reconciliation worker. Do not open this experimental route to production
commerce until scheduled reservation expiry, media eviction on bans, refunds and
payment reconciliation are implemented and tested against actual providers.

Live moderation now uses `live-control`: authenticated host ownership is verified
against the database before room deletion or participant removal through the
LiveKit server API. Ban updates DB access first; SFU cleanup can be retried on
provider failure. There is no host-only permission derived from browser input.

## Deployed rollout (2026-10-29)

The existing project now has all 15 live/commerce tables with RLS and four recorded
migrations. Six functions are deployed: live-token, live-control, stripe-connect,
stripe-checkout, stripe-webhook and integration-health. A Stripe test webhook is
registered for completed, asynchronous-success and asynchronous-failure checkout
events. Its signing secret is in Supabase Vault; no credential is in this repository.

Stripe now uses SDK 23.0.0, Accounts v2 recipient capabilities, hosted onboarding,
dynamic checkout methods and signed asynchronous-payment events. The fixed
server-only config reader supports Vault or Edge Function Secrets, with environment
values taking priority and a 30-second process cache. It accepts test restricted
keys (STRIPE_RESTRICTED_KEY) and test secret keys for compatibility.

Anonymous and authenticated roles cannot execute the credential reader. Only
service_role can read the allowlisted integration values. The public health endpoint
returns configuration booleans, never credential values. Unauthorized Connect,
Checkout and live-control requests return 401; unsigned webhook requests return 400.
A rollback-only database test checked actual guest reads, denied guest writes,
chat and bidding without retaining test records.

Current readiness: webhook configured; Stripe server API key and LiveKit
configuration still absent. Account OAuth access in ChatGPT does not automatically
install keys in Edge Functions. Owner enters a test restricted key under
STRIPE_RESTRICTED_KEY in Supabase Edge Function Secrets. LiveKit still needs a
project and LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET in the same panel.
The Stripe Projects catalog returned no LiveKit provisioning service.

The retention function loop_purge_deleted is now server-only because it deletes
Auth users. Existing clients already tolerate permission denial for that maintenance
call. No accounts were deleted. A trusted retention scheduler is separate work.
