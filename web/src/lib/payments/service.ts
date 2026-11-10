/**
 * The ONE place with payment business logic: granting access, adding coins,
 * crediting creator earnings. Providers (mock, Stripe) translate their events
 * into calls on this service, so swapping providers changes nothing here.
 */
import { canReadChapter } from "@/lib/access/canReadChapter";
import { periodOf } from "@/lib/format";
import { monetizationDefaults } from "@/config/monetization";
import {
  PaymentError,
  type EarningRecord,
  type PaymentRepository,
  type ProviderName,
  type SubscriptionRecord,
  type SubscriptionStatus,
} from "./types";

const DAY = 86_400_000;

/** Split gross revenue; the platform gets the rounding remainder. */
export function splitRevenue(grossCents: number, creatorSharePct: number) {
  const pct = Math.min(100, Math.max(0, creatorSharePct));
  const creatorCents = Math.floor((grossCents * pct) / 100);
  return { creatorCents, platformCents: grossCents - creatorCents };
}

/** Distribute `total` proportionally to `weights` in whole cents (largest remainder). */
export function allocateProportionally(total: number, weights: number[]): number[] {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (sum <= 0 || total <= 0) return weights.map(() => 0);
  const exact = weights.map((w) => (total * w) / sum);
  const out = exact.map(Math.floor);
  let rest = total - out.reduce((a, b) => a + b, 0);
  const order = exact.map((e, i) => [e - Math.floor(e), i] as const).sort((a, b) => b[0] - a[0]);
  for (let k = 0; rest > 0; k = (k + 1) % order.length, rest--) out[order[k][1]] += 1;
  return out;
}

export interface ActivateSubscriptionInput {
  userId: string;
  planCode?: string;
  provider: ProviderName;
  providerSubscriptionId: string;
  providerCustomerId?: string | null;
  periodStart: Date;
  periodEnd: Date;
  cancelAtPeriodEnd?: boolean;
  /** The charge that paid for this period (initial payment or renewal). */
  payment?: { ref: string; amountCents: number; currency: string };
}

export type UnlockResult =
  | { status: "unlocked" | "already_unlocked"; balance: number }
  | { status: "insufficient_coins"; balance: number; price: number }
  | { status: "already_has_access" }
  | { status: "not_available" };

export function createPaymentService(repo: PaymentRepository, clock: () => Date = () => new Date()) {
  async function sharePctFor(creatorId: string) {
    const override = await repo.getCreatorSharePct(creatorId);
    if (override !== null) return override;
    return (await repo.getSettings()).creatorSharePct;
  }

  const service = {
    /**
     * Runs `handler` at most once per (provider, eventId). If the handler
     * throws, the claim is released so the provider's retry is processed.
     */
    async processEventOnce<T>(
      provider: string,
      eventId: string,
      type: string,
      handler: () => Promise<T>,
    ): Promise<{ duplicate: true } | { duplicate: false; result: T }> {
      const claimed = await repo.claimEvent(provider, eventId, type);
      if (!claimed) return { duplicate: true };
      try {
        return { duplicate: false, result: await handler() };
      } catch (err) {
        await repo.releaseEvent(provider, eventId);
        throw err;
      }
    },

    // ----------------------------------------------------------------- subscriptions
    async activateSubscription(input: ActivateSubscriptionInput): Promise<SubscriptionRecord> {
      const plan = await repo.getPlanByCode(input.planCode ?? "monthly");
      if (!plan || plan.kind !== "subscription") throw new PaymentError("plan_not_found", input.planCode);
      if (input.payment) {
        await repo.recordPayment({
          userId: input.userId,
          kind: "subscription",
          planId: plan.id,
          provider: input.provider,
          providerRef: input.payment.ref,
          amountCents: input.payment.amountCents,
          currency: input.payment.currency.toUpperCase(),
          period: periodOf(clock()),
        });
      }
      return repo.upsertSubscription({
        userId: input.userId,
        planId: plan.id,
        provider: input.provider,
        providerSubscriptionId: input.providerSubscriptionId,
        providerCustomerId: input.providerCustomerId ?? null,
        status: "active",
        currentPeriodStart: input.periodStart,
        currentPeriodEnd: input.periodEnd,
        cancelAtPeriodEnd: input.cancelAtPeriodEnd ?? false,
        canceledAt: null,
      });
    },

    async setSubscriptionStatus(
      providerSubscriptionId: string,
      patch: { status?: SubscriptionStatus; cancelAtPeriodEnd?: boolean; periodStart?: Date; periodEnd?: Date },
    ) {
      return repo.updateSubscription(providerSubscriptionId, {
        ...(patch.status && { status: patch.status }),
        ...(patch.cancelAtPeriodEnd !== undefined && { cancelAtPeriodEnd: patch.cancelAtPeriodEnd }),
        ...(patch.periodStart && { currentPeriodStart: patch.periodStart }),
        ...(patch.periodEnd && { currentPeriodEnd: patch.periodEnd }),
        ...(patch.status === "canceled" && { canceledAt: clock() }),
      });
    },

    /** User asked to cancel: keep access until the end of the paid period. */
    async scheduleCancellation(providerSubscriptionId: string) {
      return repo.updateSubscription(providerSubscriptionId, { cancelAtPeriodEnd: true, canceledAt: clock() });
    },

    /** Subscription ended (period over / provider deleted it): access stops now. */
    async expireSubscription(providerSubscriptionId: string) {
      const sub = await repo.findSubscriptionByProviderId(providerSubscriptionId);
      if (!sub) return null;
      const now = clock();
      return repo.updateSubscription(providerSubscriptionId, {
        status: "expired",
        currentPeriodEnd: sub.currentPeriodEnd < now ? sub.currentPeriodEnd : now,
      });
    },

    async findActiveSubscription(userId: string) {
      return repo.findActiveSubscription(userId, clock());
    },

    // ----------------------------------------------------------------- coins
    /** A paid coin pack. Idempotent per paymentRef. */
    async creditCoinPurchase(input: {
      userId: string;
      packCode: string;
      provider: ProviderName;
      paymentRef: string;
      amountCents?: number;
      currency?: string;
    }) {
      const plan = await repo.getPlanByCode(input.packCode);
      if (!plan || plan.kind !== "coin_pack" || !plan.coins) throw new PaymentError("plan_not_found", input.packCode);
      await repo.recordPayment({
        userId: input.userId,
        kind: "coin_pack",
        planId: plan.id,
        provider: input.provider,
        providerRef: input.paymentRef,
        amountCents: input.amountCents ?? plan.priceCents,
        currency: (input.currency ?? plan.currency).toUpperCase(),
        period: periodOf(clock()),
      });
      return repo.creditCoins({
        userId: input.userId,
        amount: plan.coins,
        type: "purchase",
        planId: plan.id,
        provider: input.provider,
        ref: input.paymentRef,
      });
    },

    /** Spend coins to unlock a chapter permanently and credit the creator. */
    async unlockChapter(userId: string, chapterId: string): Promise<UnlockResult> {
      const now = clock();
      const found = await repo.getChapterForUnlock(chapterId);
      if (!found) return { status: "not_available" };
      const user = await repo.getAccessUser(userId, [chapterId], now);
      if (!user) return { status: "not_available" };
      const decision = canReadChapter({ user, series: found.series, chapter: found.chapter, now });
      if (decision.allowed) return { status: "already_has_access" };
      if (decision.reason === "not_available") return { status: "not_available" };

      const price = found.chapter.coinPrice;
      const [{ coinValueCents }, sharePct] = await Promise.all([repo.getSettings(), sharePctFor(found.series.creatorId)]);
      const grossCents = price * coinValueCents;
      const { creatorCents, platformCents } = splitRevenue(grossCents, sharePct);
      const res = await repo.applyChapterUnlock({
        userId,
        chapterId,
        price,
        creatorId: found.series.creatorId,
        seriesId: found.series.id,
        grossCents,
        creatorCents,
        platformCents,
        sharePct,
        period: periodOf(now),
      });
      if (res.status === "insufficient_coins") return { status: "insufficient_coins", balance: res.balance, price };
      return { status: res.status, balance: res.balance };
    },

    // ----------------------------------------------------------------- admin / testing
    async grantCoins(userId: string, amount: number, note?: string) {
      if (!Number.isInteger(amount) || amount === 0) throw new Error("amount must be a non-zero integer");
      return repo.creditCoins({ userId, amount, type: "admin_grant", note: note ?? null });
    },

    async grantSubscription(userId: string, days = monetizationDefaults.subscriptionPeriodDays) {
      const now = clock();
      return service.activateSubscription({
        userId,
        provider: "mock",
        providerSubscriptionId: `mock_grant_${userId}_${now.getTime()}`,
        periodStart: now,
        periodEnd: new Date(now.getTime() + days * DAY),
      });
    },

    // ----------------------------------------------------------------- creator earnings
    /**
     * Splits the creator share of a month's subscription revenue between
     * series, proportional to subscriber reads. Runs once per period.
     */
    async distributeSubscriptionPool(period: string) {
      const outcome = await service.processEventOnce("internal", `pool:${period}`, "subscription_pool", async () => {
        const [revenue, reads] = await Promise.all([repo.sumPayments(period, "subscription"), repo.subscriptionReads(period)]);
        const grossParts = allocateProportionally(revenue, reads.map((r) => r.reads));
        const rows: EarningRecord[] = [];
        for (const [i, r] of reads.entries()) {
          if (grossParts[i] <= 0) continue;
          const sharePct = await sharePctFor(r.creatorId);
          const { creatorCents, platformCents } = splitRevenue(grossParts[i], sharePct);
          rows.push({
            creatorId: r.creatorId,
            seriesId: r.seriesId,
            chapterId: null,
            source: "subscription_pool",
            grossCents: grossParts[i],
            creatorCents,
            platformCents,
            sharePct,
            period,
            ref: `pool:${period}:${r.seriesId}`,
          });
        }
        if (rows.length) await repo.insertEarnings(rows);
        return { revenue, rows: rows.length };
      });
      return outcome.duplicate ? { status: "already_distributed" as const } : { status: "ok" as const, ...outcome.result };
    },
  };
  return service;
}

export type PaymentService = ReturnType<typeof createPaymentService>;
