/** Provider-agnostic payment contracts. */
import type { AccessUser } from "@/lib/access/canReadChapter";
import type { AccessChapter, AccessSeries } from "@/lib/access/canReadChapter";

export type ProviderName = "mock" | "stripe";
export type SubscriptionStatus = "active" | "canceled" | "expired" | "past_due";
export type PlanKind = "subscription" | "coin_pack";

export interface CheckoutRequest {
  userId: string;
  email: string;
  /** pricing_plans.code */
  planCode: string;
  successUrl: string;
  cancelUrl: string;
}

export interface RedirectResult {
  url: string;
}

export interface WebhookInput {
  rawBody: string;
  signature: string | null;
}

export interface WebhookResult {
  status: "processed" | "duplicate" | "ignored";
  eventId: string;
  type: string;
}

/** Everything the app needs from a payment provider. */
export interface PaymentProvider {
  readonly name: ProviderName;
  createSubscriptionCheckout(req: CheckoutRequest): Promise<RedirectResult>;
  createCoinCheckout(req: CheckoutRequest): Promise<RedirectResult>;
  openBillingPortal(req: { userId: string; returnUrl: string }): Promise<RedirectResult>;
  handleWebhookEvent(input: WebhookInput): Promise<WebhookResult>;
  /** Cancels at period end (access continues until then). */
  cancelSubscription(req: { userId: string }): Promise<void>;
}

export class PaymentError extends Error {
  constructor(
    public readonly code:
      | "plan_not_found"
      | "no_customer"
      | "no_subscription"
      | "already_subscribed"
      | "invalid_signature"
      | "invalid_session"
      | "misconfigured",
    message?: string,
  ) {
    super(message ?? code);
    this.name = "PaymentError";
  }
}

// ---------------------------------------------------------------------------
// Persistence port used by the shared service (Supabase in the app, in-memory in tests)
// ---------------------------------------------------------------------------
export interface Plan {
  id: string;
  kind: PlanKind;
  code: string;
  name: string;
  priceCents: number;
  currency: string;
  coins: number | null;
  stripePriceId: string | null;
}

export interface SubscriptionRecord {
  id: string;
  userId: string;
  planId: string | null;
  provider: ProviderName;
  providerSubscriptionId: string;
  providerCustomerId: string | null;
  status: SubscriptionStatus;
  currentPeriodStart: Date;
  currentPeriodEnd: Date;
  cancelAtPeriodEnd: boolean;
  canceledAt: Date | null;
}

export type SubscriptionUpsert = Omit<SubscriptionRecord, "id">;

export interface PaymentRecord {
  userId: string;
  kind: PlanKind;
  planId: string | null;
  provider: ProviderName;
  providerRef: string;
  amountCents: number;
  currency: string;
  period: string; // YYYY-MM-01
}

export interface EarningRecord {
  creatorId: string;
  seriesId: string | null;
  chapterId: string | null;
  source: "coin_unlock" | "subscription_pool";
  grossCents: number;
  creatorCents: number;
  platformCents: number;
  sharePct: number;
  period: string;
  ref: string;
}

export interface CoinCreditArgs {
  userId: string;
  amount: number;
  type: "purchase" | "admin_grant" | "refund";
  planId?: string | null;
  provider?: ProviderName | null;
  ref?: string | null;
  note?: string | null;
}

export interface UnlockArgs {
  userId: string;
  chapterId: string;
  price: number;
  creatorId: string;
  seriesId: string;
  grossCents: number;
  creatorCents: number;
  platformCents: number;
  sharePct: number;
  period: string;
}

export interface PaymentRepository {
  getPlanByCode(code: string): Promise<Plan | null>;
  getPlanById(id: string): Promise<Plan | null>;
  getSettings(): Promise<{ creatorSharePct: number; coinValueCents: number }>;
  getCreatorSharePct(creatorId: string): Promise<number | null>;

  claimEvent(provider: string, eventId: string, type: string): Promise<boolean>;
  releaseEvent(provider: string, eventId: string): Promise<void>;

  /** false if a payment with the same providerRef already exists */
  recordPayment(p: PaymentRecord): Promise<boolean>;

  upsertSubscription(s: SubscriptionUpsert): Promise<SubscriptionRecord>;
  findSubscriptionByProviderId(providerSubscriptionId: string): Promise<SubscriptionRecord | null>;
  /** Latest subscription of the user that is active (status active, period not over). */
  findActiveSubscription(userId: string, now: Date): Promise<SubscriptionRecord | null>;
  updateSubscription(
    providerSubscriptionId: string,
    patch: Partial<Omit<SubscriptionRecord, "id" | "providerSubscriptionId">>,
  ): Promise<SubscriptionRecord | null>;

  creditCoins(args: CoinCreditArgs): Promise<{ status: "ok" | "duplicate"; balance: number }>;
  getBalance(userId: string): Promise<number>;

  getChapterForUnlock(
    chapterId: string,
  ): Promise<{ chapter: AccessChapter; series: AccessSeries & { id: string } } | null>;
  getAccessUser(userId: string, chapterIds: string[], now: Date): Promise<AccessUser | null>;
  applyChapterUnlock(
    args: UnlockArgs,
  ): Promise<{ status: "unlocked" | "already_unlocked" | "insufficient_coins"; balance: number }>;

  getCustomerId(userId: string, provider: ProviderName): Promise<string | null>;
  saveCustomerId(userId: string, provider: ProviderName, customerId: string): Promise<void>;

  sumPayments(period: string, kind: PlanKind): Promise<number>;
  /** Reads made with access_reason = subscription, grouped. */
  subscriptionReads(period: string): Promise<{ creatorId: string; seriesId: string; reads: number }[]>;
  insertEarnings(rows: EarningRecord[]): Promise<void>;
}
