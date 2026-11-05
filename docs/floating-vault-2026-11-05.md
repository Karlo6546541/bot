# Subhasto: Pozornica, Studio, Trezor

Navigation now has three destinations. The frosted island floats over content,
shrinks while a vertical list moves and expands after scrolling stops. In a live
room the handle stays small: swipe up opens the existing shop; tap the line opens
the three destinations. Existing category gestures and old deep links still work.
Toasts are lifted above the island so a successful bid cannot block navigation.

Trezor combines purchases and account access. Purchase type segments remain in a
glass header; statuses group orders in the list. Wallet tickets use the actual
product image, price, date and seller. The three delivery points are driven by
existing order states. Unpaid, refunded, cancelled and unknown online orders do
not light the paid step. A decorative pulse never advances a shipment.

Studio retains seller onboarding, Stripe status, inventory, financials, messages,
shows, offers and account health. Its tiles show current counts and real
conversation avatars. Inventory and the personal shop use photographic posters;
missing photos use category artwork. Auctions use large seller posters and a
floating add action. The camera pulse and health ring entry animations respect
reduced motion. Private seller details can be edited inside the personal account
using the same validation and durable save path.

Financials include an available-balance hero, a swipeable transaction deck with
keyboard-friendly previous/next controls and device haptics, plus monthly report
previews with daily earnings bars and a CSV export to the clipboard. Existing
weekly exports and payout controls remain accessible. Transaction history uses
quiet surfaces and a continuous timeline. Shipment cards use status-coloured
lines; two-finger selection includes only packages ready for handover. Normal
checkbox/select-all controls remain available. A multi-touch selection cannot
also open a shipment detail page.

Messages use hairline separators. Spotlight search starts with one field over a
blurred surface and reveals contextual suggestions after typing. Notifications
put important actions before updates. A pending online order can be reviewed and
paid inline with a deliberate slide using the existing server order, delivery,
saved-card PaymentIntent and bank-authentication flow. Paid notifications cannot
start this payment action. Nothing creates a paid state before Stripe confirms it.

The wallet renders saved payment-method metadata as a digital card, with the
address below it. Full card numbers and CVC never enter this visual component.
A mandatory Face ID/Touch ID check for editing an address has not been added:
this web app has no platform biometric credential verification flow. Payment
verification remains with Stripe and the customer's bank; the UI does not imitate
biometric approval.

## Recovery

Before editing, commit `e3df86c162f947c8f45d78529e1f1a1de20ab337` was preserved on
`backup/subhasto-before-floating-vault-2026-11-04`. A complete tracked source archive
is also saved at `/workspace/shared/subhasto-before-floating-vault-2026-11-04.tar.gz`.
The Pages workflow still publishes every older application copy, including
`/bot/prije-visionos-2026-11-04/`. No SQL schema, Stripe secrets, webhook handler,
account identity or payment fee calculation is changed by this UI release.

## Verification

Flutter analysis is clean, all 366 tests pass, and the release-web fixture builds.
All 42 phone/desktop and light/dark browser configurations pass, including
interactions for the live shop, floating dock, monthly reports and Spotlight.
Browser previews use only `tool/redesign_preview.dart` and an isolated in-memory
fixture. They do not create production users, shipments or charges.
