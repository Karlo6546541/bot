# Faithful VisionOS controls and glass sheets

Visual source: `docs/design/subhasto-visionos-reference.html`. This follows the supplied header, full video stage, chat above the bid dock, thin countdown, slide control and 70% glass catalog. Functional data and provider decisions remain in the existing services.

- Home is limited to 480 px for the reference layout, with Seller / Receipts / Search capsules. Live categories precede secondary browsing shortcuts. Search expands in place; submitting opens the existing full search with its query. Messages, profile, notifications and every browsing mode remain accessible. The main home removes the bottom dock; other sections retain normal navigation.
- Seller and receipts open as 80% glass panels. Existing private seller saving and account preparation stay unchanged. Purchase confirmation is a blurred glass panel over the item. It uses the application palette even when opened inside an always-dark live, keeping light-mode text readable.
- `VisionLiveShopOverlay` retains the room and video widget while its catalog opens. Swipe up on the bottom handle, swipe down on the drawer handle, tap outside, use Close or Back. Scrolling products does not dismiss the catalog. Hidden drawer/underlay semantics are excluded appropriately.
- `VisionBidSlider` requires a completed horizontal gesture (85% at release). Taps, partial swipes and cancelled drags do not bid. A new amount/lot cancels the active gesture. One pending callback disables duplicates. Keyboard and accessibility activation remain supported. Existing authenticated bid methods still determine permission and results.
- The live catalog defaults to Buy now for viewers; the host starts in the auction queue. Giveaway/sold tabs appear when they contain items. Custom bid, wallet, promotion and moderation remain in More. The cloud live room shares the same slide/drawer components and existing bid/login checks.
- Glass matches the reference: regular 45% cool grey, heavy drawer 65%, payment 85%, white borders and 25/40 px blur. Normal/dark themes and enlarged text remain supported.

## Saved source

Before this refinement, saved commit `c43e8881bcd66bc51448c507a5f8a3bbbdc6af81` to `backup/subhasto-before-glass-swipe-2026-11-04` and `/workspace/shared/subhasto-before-glass-swipe-2026-11-04.tar.gz`. Existing public historical copies, including `/bot/prije-visionos-2026-11-04/`, are retained unchanged.

## Validation

The full Flutter suite includes a payment contrast regression and five new gesture tests (incomplete gestures, amount changes mid-drag, pending duplicates, keyboard activation and drawer/video continuity). Existing live, authenticated cloud, seller persistence and purchase tests exercise the new controls. Release browser checks perform actual pointer swipes, open seller/receipts glass panels and exercise inline search. No production payment is initiated by verification.
