# Photographic glass stage

The separate Flutter preview at `/bot/novi-izgled/` now follows the user's
screenshot: a floating frosted header, photographic hero, white primary action,
black dark theme, and two smaller live cards with thin borders and yellow accents.
The main app keeps its existing design through `SIMPLE_DESIGN=false`.

The header's seller and receipts capsules open the existing Studio and Trezor.
Search expands the existing search, messages, notifications and discovery controls.
Live/Shop controls stay visible in Shop or when search is expanded; horizontal
swipe still switches between live discovery and Shop. The three destination dock,
legacy deep links and original application functions remain available.

Live prices come only from the current running lot. When there is no live show,
a real available shop item fills the hero, with a Shop caption and a View action
that opens the existing product flow. No live room, viewer count or price is
invented to fill the design.

Header capsules scale within the available width; enlarged text wraps the actions.
Video/payment controls and their contrast keep the existing implementation.
No database, authentication, seller save, payment or Stripe Connect logic changed.

## Recovery

Previous preview source is saved at `7cdd924751b4de7df7724fceabbd2faac622378c`
on `backup/subhasto-before-glass-stage-2026-11-05` and in
`/workspace/shared/subhasto-before-glass-stage-2026-11-05.tar.gz`.
Archive SHA256: `7ffddc7361857f498d1843ecd7c6462caf0fce7ce2ad67132884558c891b19db`.
The main application and all saved public copies remain in the Pages workflow.

## Validation

The existing 367-test suite, 30 preview flow tests, static analysis, formatting and
42 browser scenarios cover the change. Browser scenarios use an isolated fixture,
with no real account changes or charges. Production smoke checks also remain
read-only and use guest navigation.
