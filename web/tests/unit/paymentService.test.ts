import { beforeEach, describe, expect, it } from "vitest";
import { allocateProportionally, createPaymentService, splitRevenue } from "@/lib/payments/service";
import { createMemoryRepository, DAY, seedChapter } from "./helpers/memoryRepository";

const NOW = new Date("2026-11-10T12:00:00Z");

describe("pure helpers", () => {
  it("splitRevenue gives the creator floor(gross*pct) and the platform the rest", () => {
    expect(splitRevenue(1000, 65)).toEqual({ creatorCents: 650, platformCents: 350 });
    expect(splitRevenue(50, 65)).toEqual({ creatorCents: 32, platformCents: 18 });
    expect(splitRevenue(99, 100)).toEqual({ creatorCents: 99, platformCents: 0 });
    expect(splitRevenue(99, 150)).toEqual({ creatorCents: 99, platformCents: 0 });
  });

  it("allocateProportionally preserves the total exactly", () => {
    const parts = allocateProportionally(1000, [1, 1, 1]);
    expect(parts.reduce((a, b) => a + b, 0)).toBe(1000);
    expect(parts.sort()).toEqual([333, 333, 334]);
    expect(allocateProportionally(0, [1, 2])).toEqual([0, 0]);
    expect(allocateProportionally(100, [0, 0])).toEqual([0, 0]);
    expect(allocateProportionally(100, [3, 1])).toEqual([75, 25]);
  });
});

describe("PaymentService", () => {
  let mem: ReturnType<typeof createMemoryRepository>;
  let svc: ReturnType<typeof createPaymentService>;
  beforeEach(() => {
    mem = createMemoryRepository();
    svc = createPaymentService(mem.repo, () => NOW);
    mem.state.users.set("u1", { role: "reader" });
  });

  describe("subscriptions", () => {
    it("activates, records the payment, and is idempotent per payment ref", async () => {
      const input = {
        userId: "u1",
        provider: "mock" as const,
        providerSubscriptionId: "sub_1",
        periodStart: NOW,
        periodEnd: new Date(NOW.getTime() + 30 * DAY),
        payment: { ref: "pay_1", amountCents: 499, currency: "eur" },
      };
      await svc.activateSubscription(input);
      await svc.activateSubscription(input);
      expect(mem.state.subs).toHaveLength(1);
      expect(mem.state.payments).toEqual([
        expect.objectContaining({ kind: "subscription", amountCents: 499, currency: "EUR", period: "2026-11-01" }),
      ]);
      expect(await svc.findActiveSubscription("u1")).toMatchObject({ status: "active" });
    });

    it("cancellation keeps access until period end; expiry removes it", async () => {
      await svc.activateSubscription({
        userId: "u1",
        provider: "mock",
        providerSubscriptionId: "sub_1",
        periodStart: NOW,
        periodEnd: new Date(NOW.getTime() + 30 * DAY),
      });
      await svc.scheduleCancellation("sub_1");
      expect(await svc.findActiveSubscription("u1")).toMatchObject({ cancelAtPeriodEnd: true });
      await svc.expireSubscription("sub_1");
      expect(await svc.findActiveSubscription("u1")).toBeNull();
      expect(mem.state.subs[0].status).toBe("expired");
    });

    it("rejects unknown plans", async () => {
      await expect(
        svc.activateSubscription({ userId: "u1", planCode: "nope", provider: "mock", providerSubscriptionId: "x", periodStart: NOW, periodEnd: NOW }),
      ).rejects.toMatchObject({ code: "plan_not_found" });
    });
  });

  describe("coins", () => {
    it("credits a coin pack once per payment ref", async () => {
      const r1 = await svc.creditCoinPurchase({ userId: "u1", packCode: "coins_50", provider: "stripe", paymentRef: "pi_1" });
      const r2 = await svc.creditCoinPurchase({ userId: "u1", packCode: "coins_50", provider: "stripe", paymentRef: "pi_1" });
      expect(r1).toEqual({ status: "ok", balance: 50 });
      expect(r2).toEqual({ status: "duplicate", balance: 50 });
      expect(mem.state.payments).toHaveLength(1);
    });

    it("refuses to credit a subscription plan as coins", async () => {
      await expect(
        svc.creditCoinPurchase({ userId: "u1", packCode: "monthly", provider: "mock", paymentRef: "x" }),
      ).rejects.toMatchObject({ code: "plan_not_found" });
    });
  });

  describe("unlockChapter", () => {
    it("spends coins, unlocks permanently and credits the creator (65/35)", async () => {
      const ch = seedChapter(mem.state, { now: NOW });
      mem.state.balances.set("u1", 12);
      expect(await svc.unlockChapter("u1", ch)).toEqual({ status: "unlocked", balance: 7 });
      expect(mem.state.earnings).toEqual([
        expect.objectContaining({ creatorId: "creator-1", grossCents: 50, creatorCents: 32, platformCents: 18, sharePct: 65, period: "2026-11-01" }),
      ]);
      // now readable -> second attempt does not charge
      expect(await svc.unlockChapter("u1", ch)).toEqual({ status: "already_has_access" });
      expect(mem.state.balances.get("u1")).toBe(7);
    });

    it("uses the creator's override share and configured coin value", async () => {
      const ch = seedChapter(mem.state, { now: NOW, price: 10 });
      mem.state.creatorShare.set("creator-1", 80);
      mem.state.settings.coinValueCents = 8;
      mem.state.balances.set("u1", 10);
      await svc.unlockChapter("u1", ch);
      expect(mem.state.earnings[0]).toMatchObject({ grossCents: 80, creatorCents: 64, platformCents: 16, sharePct: 80 });
    });

    it("insufficient coins: nothing changes", async () => {
      const ch = seedChapter(mem.state, { now: NOW });
      mem.state.balances.set("u1", 4);
      expect(await svc.unlockChapter("u1", ch)).toEqual({ status: "insufficient_coins", balance: 4, price: 5 });
      expect(mem.state.unlocks.size).toBe(0);
      expect(mem.state.earnings).toHaveLength(0);
    });

    it("does not charge for chapters that are free or covered by a subscription", async () => {
      const free = seedChapter(mem.state, { now: NOW, chapterId: "ch-1", number: 1 });
      mem.state.balances.set("u1", 50);
      expect(await svc.unlockChapter("u1", free)).toEqual({ status: "already_has_access" });
      const locked = seedChapter(mem.state, { now: NOW });
      await svc.grantSubscription("u1", 30);
      expect(await svc.unlockChapter("u1", locked)).toEqual({ status: "already_has_access" });
      expect(mem.state.balances.get("u1")).toBe(50);
    });

    it("refuses unavailable chapters (unknown, scheduled, hidden)", async () => {
      expect(await svc.unlockChapter("u1", "missing")).toEqual({ status: "not_available" });
      const ch = seedChapter(mem.state, { now: NOW });
      mem.state.chapters.get(ch)!.series.hiddenByAdmin = true;
      mem.state.balances.set("u1", 50);
      expect(await svc.unlockChapter("u1", ch)).toEqual({ status: "not_available" });
    });
  });

  describe("processEventOnce", () => {
    it("runs a handler once per event id and releases the claim on failure", async () => {
      let calls = 0;
      const ok = () => svc.processEventOnce("stripe", "evt_1", "t", async () => ++calls);
      expect(await ok()).toEqual({ duplicate: false, result: 1 });
      expect(await ok()).toEqual({ duplicate: true });

      await expect(svc.processEventOnce("stripe", "evt_2", "t", async () => { throw new Error("boom"); })).rejects.toThrow("boom");
      expect(await svc.processEventOnce("stripe", "evt_2", "t", async () => "retried")).toEqual({ duplicate: false, result: "retried" });
    });
  });

  describe("distributeSubscriptionPool", () => {
    it("splits subscription revenue by subscriber reads, once per period", async () => {
      mem.state.payments.push(
        { userId: "a", kind: "subscription", planId: null, provider: "mock", providerRef: "p1", amountCents: 600, currency: "EUR", period: "2026-11-01" },
        { userId: "b", kind: "subscription", planId: null, provider: "mock", providerRef: "p2", amountCents: 400, currency: "EUR", period: "2026-11-01" },
        { userId: "c", kind: "coin_pack", planId: null, provider: "mock", providerRef: "p3", amountCents: 999, currency: "EUR", period: "2026-11-01" },
      );
      mem.state.reads.push(
        { creatorId: "cA", seriesId: "s1", period: "2026-11-01" },
        { creatorId: "cA", seriesId: "s1", period: "2026-11-01" },
        { creatorId: "cA", seriesId: "s1", period: "2026-11-01" },
        { creatorId: "cB", seriesId: "s2", period: "2026-11-01" },
        { creatorId: "cB", seriesId: "s3", period: "2026-10-01" }, // other month
      );
      const res = await svc.distributeSubscriptionPool("2026-11-01");
      expect(res).toEqual({ status: "ok", revenue: 1000, rows: 2 });
      const byCreator = Object.fromEntries(mem.state.earnings.map((e) => [e.creatorId, e]));
      expect(byCreator.cA).toMatchObject({ grossCents: 750, creatorCents: 487, platformCents: 263, source: "subscription_pool" });
      expect(byCreator.cB).toMatchObject({ grossCents: 250, creatorCents: 162, platformCents: 88 });
      expect(await svc.distributeSubscriptionPool("2026-11-01")).toEqual({ status: "already_distributed" });
      expect(mem.state.earnings).toHaveLength(2);
    });
  });

  it("admin grants: coins and a mock subscription", async () => {
    expect(await svc.grantCoins("u1", 30)).toEqual({ status: "ok", balance: 30 });
    await expect(svc.grantCoins("u1", 0)).rejects.toThrow();
    await svc.grantSubscription("u1", 7);
    const sub = await svc.findActiveSubscription("u1");
    expect(sub?.currentPeriodEnd.getTime()).toBe(NOW.getTime() + 7 * DAY);
    expect(mem.state.payments).toHaveLength(0); // no money changed hands
  });
});
