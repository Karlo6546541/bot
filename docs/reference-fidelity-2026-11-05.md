# Subhasto: fidelity corrections, 5 November 2026

The user's `jednostavno` artboard is the reference, including its secondary sheets.
This change corrects the optional `SIMPLE_DESIGN=true` version at `/bot/novi-izgled/`.
The default application remains available at `/bot/`.

## Layout

- Home uses Inter, a 34px wordmark, 44px message controls, one 48px search button,
  44px category pills, scrolling header and a floating dock inset 28px.
- Purchases use 68px receipt rows with 52px artwork. Delivery progress and payment
  actions open on tap, instead of occupying each list row. Status remains visible.
- Search opens in a 90% glass sheet with one 52px input at the top, suggestions,
  mixed shop and item results. Existing kind and show filters remain available.
- Secondary destinations use the same rounded sheet and close control. Existing
  share, seller information, notification preferences, tabs, creation and export
  actions remain available. Inter applies to body text as well as headings.
- Sheets fit above the keyboard. Reduced-motion preferences are respected.

## Functional boundaries

Existing account ownership checks, data persistence, payment confirmation,
server price verification, card handling and shipping operations are reused.
No Stripe/Supabase configuration, secrets, schemas or payment amounts change.
Unpaid orders never display a completed payment step. An unassigned legacy
shipment remains awaiting dispatch, rather than appearing delivered.

## Saved version

Before editing, commit `9db9db273d00bf8bb0b2868800f422363896ba49` was preserved
as branch `backup/subhasto-before-fidelity-2026-11-05`.
Source archive: `subhasto-before-fidelity-2026-11-05.tar.gz`.
SHA256: `e191f5310a54e4210fb8d4720b724c02897e9997c37f08da775c708c4d368eba`.

## Verification

The preview tests cover six visible purchase rows at phone size, opening and
closing delivery details, keyboard insets, real shop search, accessible shop
information/share controls, activity sections, seller tools and existing
payment/onboarding flows. Browser previews exercise the mobile Android user
agent as well as wide viewports and both themes. Screens are compared against
the supplied artboard rather than validating labels alone.
