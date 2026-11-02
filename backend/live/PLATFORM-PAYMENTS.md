# Subhasto test payments

The application uses the existing platform `acct_1UVqd9PdLAWyn74E` in test mode. This is the application's Stripe balance; it is not a newly opened bank account. Stripe processing costs are separate from Subhasto revenue.

- Card details are collected by Stripe Payment Element in `stripe-payment.html`. Subhasto never receives the card number or CVC. A SetupIntent creates/saves the payment method on the authenticated user's Customer profile, with recorded consent for requested future purchases and promotions.
- Sellers get their own Accounts v2 recipient account through authenticated Subhasto onboarding. A buyer's saved card is not a payout bank account. Seller verification and Stripe terms must be completed by the seller.
- Buy now on existing seller listings creates an authoritative `commerce_orders` record. Choosing delivery triggers a saved-card PaymentIntent. Issuer authentication resumes that same intent inside the app. Per-purchase Checkout is disabled.
- Fees are rounded in cents: `(item_cents * 6 + 50) / 100`. Shipping is separate; the current locker flow is a zero-cost demo. A 19 EUR item has a 1.14 EUR platform fee and 17.86 EUR seller share, including when a separate shipping amount is present.
- Payment confirmations are idempotent and signature verified. Customer IDs, consent, payment state, promotion purchases and the platform revenue ledger live on the server. The ledger is accessible only to the service role.
- Live promotions are charged entirely to the platform and are activated only after Stripe success. Declines, retries and refunds preserve the same purchase identity.
- Separate charges and transfers keep seller funds on the platform until the buyer confirms receipt and condition, or 48 hours after a trusted pickup event. A dispute or refund blocks release. `stripe-release` rechecks the recipient capability and Stripe charge before transferring, and uses an order-specific idempotency key. This transfers to the seller's Stripe balance; subsequent bank payouts follow Stripe's payout schedule.
- `subhasto-test-seller-release` runs once per minute. Its private job credential is generated in Vault and is never returned to an app client. Browsers cannot create a pickup event or select a transfer destination/amount. Existing carrier simulation is not trusted pickup evidence.

## Configuration

Set `STRIPE_RESTRICTED_KEY` (`rk_test_`, preferred) or `STRIPE_SECRET_KEY` in Edge Function Secrets. The restricted key needs the operations used by this integration: account read, Accounts v2/Connect onboarding, customers, payment methods, SetupIntents, PaymentIntents, charge reads, transfers and reversals. Services reject live keys and keys for another platform.

Set `STRIPE_PUBLISHABLE_KEY` (`pk_test_`) for the same test platform. This is public; secret keys must never be placed in Flutter defines, HTML, chat or logs. `STRIPE_WEBHOOK_SECRET` must belong to the platform endpoint.

The webhook subscribes to Checkout completion/async success/failure for older orders, `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded` and `charge.dispute.created`. Fulfillment depends on provider success, never an iframe message or return URL.

Apply the recorded platform migration before deploying the functions. `sql/platform_schedule.sql` provisions the test scheduler. The public health response returns booleans only, including `testPlatformConnected` and `paymentFormConfigured`.

## Verification and limits

PGlite tests exercise ownership, stock reservation, payment authority, duplicate settlement, fee and shipping arithmetic, release timing, disputes, refunds and promotion fulfillment. Deno tests cover persist-before-confirm behavior and recovery from issuer authentication. Flutter analysis, tests and web builds run in GitHub Actions.

A successful build is not an end-to-end payment test. That additionally requires the publishable key, an authenticated user saving a Stripe test card and a ready recipient account for seller purchases. The older local auction, credit, swap and instant-sell demo engines remain separate from these server-owned orders; their local transaction records are not proof of a Stripe payment. Other legacy promotion types are not handled by the live-promotion endpoint.
