# Simplified Flutter preview

The subsequent screenshot-based visual refinement is documented in
[glass-stage-2026-11-05.md](glass-stage-2026-11-05.md).

The user requested an improvised redesign in the current Flutter/Dart stack,
with a separate link alongside the existing application. The Claude artifact
required sign-in, so no claim is made to reproduce its private contents.

The main app keeps its current design. `SIMPLE_DESIGN=true` selects the new view
and the Pages workflow publishes it at `/bot/novi-izgled/`, using a separate build
output directory. Both versions retain the same working application features.

The preview changes the following:

- Stage has two visible modes: live and Shop. Following, scheduled shows,
  categories, timed auctions and digital purchases remain in discovery controls.
  Context is named when selected and can be cleared in one tap. When no show is
  live, real available products fill the otherwise empty stage.
- Messages, search and notifications are directly visible in the Stage header.
- Studio has one primary live action and flat tool rows with real counts.
  The introductory panel, duplicate task tiles and duplicate tool menu are removed.
- Trezor has purchases, offers and saved items. The offers view includes both
  auction bidding activity and negotiated prices. Shipping and purchase actions
  keep their existing order, validation and payment logic.
- Quiet account/order surfaces replace decorative card borders; video controls,
  payment dialogs and the floating dock retain bounded glass for contrast.

No server schema, authentication, seller persistence, fee calculation, saved-card
charge or Stripe Connect integration is replaced or simulated by this preview.

## Recovery

Current source was saved before editing at commit
`0bc1e127d52fc08942008a66e5b261a209e64ae5`, on branch
`backup/subhasto-before-artifact-design-2026-11-05` and in
`/workspace/shared/subhasto-before-artifact-design-2026-11-05.tar.gz`.
Its SHA256 is `047b517be3bd316fef7a27435e557ab60f7255b0f5b0feb9e03074769268071d`.
Previously saved public application copies remain in the Pages workflow.

## Validation

Verified locally with Flutter 3.47.7:

- `flutter analyze`: no issues; changed Dart files pass the formatter.
- Default application: all 367 tests passed.
- `SIMPLE_DESIGN=true`: all 30 selected flow tests passed, covering navigation,
  combined bids/offers, inline purchase validation, account editing, durable seller
  save, duplicate-save protection and the unavailable-Stripe state.
- All 42 browser scenarios passed on mobile and desktop, in light and dark themes.
  Browser previews use the existing in-memory `tool/redesign_preview.dart` fixture,
  with no real charges or users.
- The real `lib/main.dart` release build with online commerce and the preview flag
  succeeds at `/bot/novi-izgled/`. Its separate output directory leaves the existing
  `build/web/main.dart.js` unchanged (SHA256 checked).

CI repeats the normal suite and the 30 preview flow tests. The Pages workflow builds
and publishes both versions and all previously saved public application copies.
