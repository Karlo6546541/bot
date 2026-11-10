import type { Database } from "./database.types";

type T = Database["public"]["Tables"];
export type Profile = T["profiles"]["Row"];
export type Creator = T["creators"]["Row"];
export type Series = T["series"]["Row"];
export type Chapter = T["chapters"]["Row"];
export type ChapterPage = T["chapter_pages"]["Row"];
export type Subscription = T["subscriptions"]["Row"];
export type PricingPlan = T["pricing_plans"]["Row"];
export type CreatorEarning = T["creator_earnings"]["Row"];
export type UserRole = Database["public"]["Enums"]["user_role"];
export type ChapterAccessType = Database["public"]["Enums"]["chapter_access"];
