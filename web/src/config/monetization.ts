/**
 * Monetization defaults. The live values are read from the DB tables
 * `pricing_plans` and `platform_settings` (editable by admins); these are only
 * used as fallbacks and to seed the DB (see supabase/seed.sql).
 */
export const monetizationDefaults = {
  currency: "EUR",
  /** Share of revenue credited to the creator, in percent. */
  creatorSharePct: 65,
  /** Accounting value of one coin when crediting creator earnings (cents). */
  coinValueCents: 10,
  defaultCoinPrice: 5,
  defaultFreeChapters: 3,
  /** Lifetime of signed page-image URLs (seconds). */
  signedUrlTtlSeconds: 300,
  subscriptionPeriodDays: 30,
  plans: [
    { kind: "subscription", code: "monthly", name: "Mjesečna pretplata", priceCents: 499, coins: null },
    { kind: "coin_pack", code: "coins_50", name: "50 novčića", priceCents: 499, coins: 50 },
    { kind: "coin_pack", code: "coins_120", name: "120 novčića", priceCents: 999, coins: 120 },
    { kind: "coin_pack", code: "coins_300", name: "300 novčića", priceCents: 1999, coins: 300 },
  ],
} as const;

export const GENRES = [
  "action",
  "adventure",
  "comedy",
  "drama",
  "fantasy",
  "horror",
  "mystery",
  "romance",
  "scifi",
  "slice_of_life",
  "history",
] as const;
export type Genre = (typeof GENRES)[number];
