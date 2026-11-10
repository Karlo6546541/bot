import { beforeEach, describe, expect, it } from "vitest";
import { createPaymentService } from "@/lib/payments/service";
import { decodeSession, MockPaymentProvider } from "@/lib/payments/mock/provider";
import { createMemoryRepository, DAY } from "./helpers/memoryRepository";

const NOW = new Date("2026-11-10T12:00:00Z");
const req = (planCode: string) => ({
  userId: "u1",
  email: "u1@kadar.test",
  planCode,
  successUrl: "http://localhost:3000/checkout/success?kind=x",
  cancelUrl: "http://localhost:3000/checkout/canceled",
});
const tokenOf = (url: string) => new URL(url, "http://x").searchParams.get("session")!;

describe("MockPaymentProvider", () => {
  let mem: ReturnType<typeof createMemoryRepository>;
  let provider: MockPaymentProvider;
  let ids = 0;
  beforeEach(() => {
    mem = createMemoryRepository();
    mem.state.users.set("u1", { role: "reader" });
    const service = createPaymentService(mem.repo, () => NOW);
    provider = new MockPaymentProvider({ service, repo: mem.repo, clock: () => NOW, newId: () => `id${++ids}` });
  });

  it("checkout points to the internal mock page, never an external URL", async () => {
    const { url } = await provider.createCoinCheckout(req("coins_50"));
    expect(url.startsWith("/checkout/mock?session=")).toBe(true);
    const s = decodeSession(tokenOf(url), NOW.getTime());
    expect(s).toMatchObject({ kind: "coins", planCode: "coins_50", userId: "u1", successUrl: "/checkout/success?kind=x" });
  });

  it("successful coin checkout writes payment + coins exactly once", async () => {
    const { url } = await provider.createCoinCheckout(req("coins_120"));
    const r1 = await provider.completeCheckout(tokenOf(url), "success", "u1");
    const r2 = await provider.completeCheckout(tokenOf(url), "success", "u1"); // double click / replay
    expect(r1.status).toBe("processed");
    expect(r2.status).toBe("duplicate");
    expect(mem.state.balances.get("u1")).toBe(120);
    expect(mem.state.payments).toEqual([expect.objectContaining({ kind: "coin_pack", amountCents: 999, provider: "mock" })]);
  });

  it("failed checkout grants nothing", async () => {
    const { url } = await provider.createSubscriptionCheckout(req("monthly"));
    await provider.completeCheckout(tokenOf(url), "failure", "u1");
    expect(mem.state.subs).toHaveLength(0);
    expect(mem.state.payments).toHaveLength(0);
  });

  it("another user cannot complete my checkout session", async () => {
    const { url } = await provider.createCoinCheckout(req("coins_50"));
    await expect(provider.completeCheckout(tokenOf(url), "success", "u2")).rejects.toMatchObject({ code: "invalid_session" });
    expect(mem.state.balances.size).toBe(0);
  });

  it("rejects tampered / expired sessions and unknown plans", async () => {
    await expect(provider.completeCheckout("garbage", "success", "u1")).rejects.toMatchObject({ code: "invalid_session" });
    const { url } = await provider.createCoinCheckout(req("coins_50"));
    expect(() => decodeSession(tokenOf(url), NOW.getTime() + 2 * 3600_000)).toThrow();
    await expect(provider.createCoinCheckout(req("monthly"))).rejects.toMatchObject({ code: "plan_not_found" });
  });

  it("subscription lifecycle: subscribe → cancel → expire, plus renew", async () => {
    const { url } = await provider.createSubscriptionCheckout(req("monthly"));
    await provider.completeCheckout(tokenOf(url), "success", "u1");
    const sub = mem.state.subs[0];
    expect(sub).toMatchObject({ status: "active", provider: "mock", cancelAtPeriodEnd: false });
    expect(sub.currentPeriodEnd.getTime()).toBe(NOW.getTime() + 30 * DAY);
    await expect(provider.createSubscriptionCheckout(req("monthly"))).rejects.toMatchObject({ code: "already_subscribed" });

    await provider.simulateRenew("u1");
    expect(mem.state.subs[0].currentPeriodEnd.getTime()).toBe(NOW.getTime() + 60 * DAY);
    expect(mem.state.payments.filter((p) => p.kind === "subscription")).toHaveLength(2);

    await provider.cancelSubscription({ userId: "u1" });
    expect(mem.state.subs[0]).toMatchObject({ status: "active", cancelAtPeriodEnd: true });

    await provider.simulateExpire("u1");
    expect(mem.state.subs[0].status).toBe("expired");
    expect(await mem.repo.findActiveSubscription("u1", NOW)).toBeNull();
    await expect(provider.cancelSubscription({ userId: "u1" })).rejects.toMatchObject({ code: "no_subscription" });
  });

  it("billing portal stays inside the app", async () => {
    expect(await provider.openBillingPortal({ userId: "u1", returnUrl: "/account" })).toEqual({ url: "/account#subscription" });
  });
});
