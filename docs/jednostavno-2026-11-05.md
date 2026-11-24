# Subhasto — supplied jednostavno design

The separate Flutter preview at `/bot/novi-izgled/` follows the supplied ZIP:
black canvas with quiet blue/warm ambient colour, frosted grouped surfaces,
pill controls and a floating dock. Actual photos and account records replace the
mockup's sample illustrations, balances and counts. The main application keeps
its existing design through `SIMPLE_DESIGN=false`.

The reference introduces four destinations: Home, Live, Sell and Profile. Home
has a horizontal live row, real seller shops and the product gallery; search
matches both items and their shop names. Categories and advanced discovery keep
their existing filters. Selecting Live opens an available room, or the existing
live discovery view when none is available. The room keeps its real video/chat,
shop drawer, host controls and bid actions, with a quieter current-price display
and circular countdown. The dock stays available in native and cloud rooms.

Sell groups the existing tools and shows actual current-month sale earnings.
Profile groups purchases, bids, price offers, saved items, messages, notifications,
wallet, shop and account tools. Bids and negotiated offers have separate activity
sections, matching the reference. Legacy category, order, profile and seller URLs
retain their existing meanings.

## Function map

| Existing function | Entry in the new view |
| --- | --- |
| Live video, chat, bidding, maximum bid, giveaways, queue, host/moderation tools | Live, an actual live card, or the existing room tools |
| Shop, item details, categories, filters, following, timed auctions and digital purchases | Home search/category row, Filter, Shop and existing detail flows |
| Purchases, unclaimed awards, bids, price offers and saved items | Profile activity rows |
| Saved cards, address, parcel locker/courier, inline purchase confirmation and bank authentication | Profile Wallet and the existing purchase popup |
| Tracking, receipt confirmation, refunds, disputes and digital downloads | Existing purchase and delivery details |
| Inventory, creation, auctions, scheduled shows, seller offers and messages | Sell grouped tools |
| Shipping, batch selection, labels and shipping profiles | Sell Shipping and Seller settings |
| Seller details, verification, Connect status and account health | Sell verification card; Profile seller details and account health |
| Finance, payouts, transactions and reports/CSV | Sell earnings card and Profile transaction history |
| Public shop, favourites, swaps and other account tools | Existing shop/detail, messages and Profile settings screens |
| Authentication, sign-out, language, legal/contact and privacy controls | Profile and the existing authentication/settings flows |

No database migration, Stripe integration, server amount calculation, fee rule,
permission or persistence implementation is replaced by mockup logic. Guest
navigation continues to gate private data and actions. Card/account information
comes from the existing providers rather than the reference's fixed sample data.

## Recovery and verification

Previous source is saved at `6fb994b36e2081ddd1afa6f93e957718861b04c3` on
`backup/subhasto-before-jednostavno-2026-11-05` and in
`/workspace/shared/subhasto-before-jednostavno-2026-11-05.tar.gz`.
Archive SHA256: `2a6111e17af0b388cf1ff34314831fa94209e994ba44bf0ae2fd7ce114f7429c`.
Reference templates are preserved under `docs/design/jednostavno/`.

Validation uses the existing 367-test default suite, 32 selected preview tests,
static analysis/formatting and the 42-scenario browser matrix. Preview tests cover
actual shop lookup/navigation, all four destinations, seller/account save, native
and cloud room shop drawers, payment validation, delivery and purchase privacy.
Browser fixtures are isolated; public smoke checks use guest navigation without
placing bids, sending messages or making charges.
