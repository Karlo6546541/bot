# Live commerce backend

This is an additive production backend foundation, not Whatnot's proprietary architecture.
The deployed Flutter UI still uses the legacy `LiveService` and peer-to-peer video.
`LiveBackend` is the new API adapter; switching UI ownership, identity and video controllers
is deliberately pending deployment of the real services. Do not label the demo as production.

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
