/**
 * Stripe webhook handling with fake payloads. Uses the real Stripe SDK for
 * signature generation/verification (offline); API calls are stubbed.
 */
import Stripe from "stripe";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createPaymentService } from "@/lib/payments/service";
import { mapStripeStatus, StripePaymentProvider, stripeConfigFromEnv } from "@/lib/payments/stripe/provider";
import { createMemoryRepository, DAY } from "./helpers/memoryRepository";

const NOW = new Date("2026-11-10T12:00:00Z");
const SECRET = "whsec_test_secret";
const sec = (d: Date) => Math.floor(d.getTime() / 1000);
const PERIOD_END = new Date(NOW.getTime() + 30 * DAY);

function fakeSubscription(o: Partial<Record<string, unknown>> = {}) {
  return {
    id: "sub_123",
    object: "subscription",
    status: "active",
    customer: "cus_1",
    cancel_at_period_end: false,
    start_date: sec(NOW),
    metadata: { userId: "u1", planCode: "monthly" },
    items: { object: "list", data: [{ id: "si_1", current_period_start: sec(NOW), current_period_end: sec(PERIOD_END) }] },
    ...o,
  };
}

let seq = 0;
function event(type: string, object: Record<string, unknown>, id = `evt_${++seq}`) {
  return { id, object: "event", type, api_version: "2026-10-28", created: sec(NOW), data: { object }, livemode: false };
}

describe("StripePaymentProvider webhooks", () => {
  let mem: ReturnType<typeof createMemoryRepository>;
  let stripe: Stripe;
  let provider: StripePaymentProvider;

  const deliver = (evt: object, signature?: string | null) => {
    const payload = JSON.stringify(evt);
    const sig = signature === undefined ? stripe.webhooks.generateTestHeaderString({ payload, secret: SECRET }) : signature;
    return provider.handleWebhookEvent({ rawBody: payload, signature: sig });
  };

  beforeEach(() => {
    mem = createMemoryRepository();
    mem.state.users.set("u1", { role: "reader" });
    stripe = new Stripe("sk_test_fake_key_for_unit_tests");
    vi.spyOn(stripe.subscriptions, "retrieve").mockResolvedValue(fakeSubscription() as never);
    const service = createPaymentService(mem.repo, () => NOW);
    provider = new StripePaymentProvider({
      service,
      repo: mem.repo,
      config: { secretKey: "sk_test_fake", webhookSecret: SECRET, priceIds: {} },
      stripeFactory: async () => stripe,
    });
  });

  describe("signature verification", () => {
    it("rejects a missing signature", async () => {
      await expect(deliver(event("invoice.paid", {}), null)).rejects.toMatchObject({ code: "invalid_signature" });
    });

    it("rejects a bad signature and a tampered body", async () => {
      await expect(deliver(event("invoice.paid", {}), "t=1,v1=deadbeef")).rejects.toMatchObject({ code: "invalid_signature" });
      const evt = event("checkout.session.completed", { id: "cs_1", metadata: { kind: "coins", userId: "u1", planCode: "coins_50" } });
      const sig = stripe.webhooks.generateTestHeaderString({ payload: JSON.stringify(evt), secret: SECRET });
      const tampered = JSON.stringify({ ...evt, data: { object: { ...evt.data.object, metadata: { kind: "coins", userId: "attacker", planCode: "coins_50" } } } });
      await expect(provider.handleWebhookEvent({ rawBody: tampered, signature: sig })).rejects.toMatchObject({ code: "invalid_signature" });
      expect(mem.state.balances.size).toBe(0);
    });

    it("rejects a signature made with another secret", async () => {
      const evt = event("invoice.paid", {});
      const payload = JSON.stringify(evt);
      const sig = stripe.webhooks.generateTestHeaderString({ payload, secret: "whsec_other" });
      await expect(provider.handleWebhookEvent({ rawBody: payload, signature: sig })).rejects.toMatchObject({ code: "invalid_signature" });
    });
  });

  describe("coin packs", () => {
    const paidSession = (o: Record<string, unknown> = {}) => ({
      id: "cs_coins_1",
      object: "checkout.session",
      mode: "payment",
      payment_status: "paid",
      payment_intent: "pi_1",
      customer: "cus_1",
      client_reference_id: "u1",
      amount_total: 499,
      currency: "eur",
      metadata: { kind: "coins", userId: "u1", planCode: "coins_50" },
      ...o,
    });

    it("checkout.session.completed credits coins + records payment + customer", async () => {
      const res = await deliver(event("checkout.session.completed", paidSession()));
      expect(res).toMatchObject({ status: "processed", type: "checkout.session.completed" });
      expect(mem.state.balances.get("u1")).toBe(50);
      expect(mem.state.payments).toEqual([expect.objectContaining({ providerRef: "pi_1", amountCents: 499, currency: "EUR", provider: "stripe" })]);
      expect(mem.state.customers.get("stripe:u1")).toBe("cus_1");
    });

    it("the SAME event delivered twice is processed once", async () => {
      const evt = event("checkout.session.completed", paidSession(), "evt_dup");
      expect((await deliver(evt)).status).toBe("processed");
      expect((await deliver(evt)).status).toBe("duplicate");
      expect(mem.state.balances.get("u1")).toBe(50);
    });

    it("two DIFFERENT events for the same payment intent credit once", async () => {
      await deliver(event("checkout.session.completed", paidSession()));
      await deliver(event("checkout.session.async_payment_succeeded", paidSession()));
      expect(mem.state.balances.get("u1")).toBe(50);
      expect(mem.state.payments).toHaveLength(1);
    });

    it("unpaid (async) sessions are ignored until payment succeeds", async () => {
      const res = await deliver(event("checkout.session.completed", paidSession({ payment_status: "unpaid" })));
      expect(res.status).toBe("ignored");
      expect(mem.state.balances.size).toBe(0);
    });

    it("a failing handler releases the event so Stripe's retry works", async () => {
      const evt = event("checkout.session.completed", paidSession({ metadata: { kind: "coins", userId: "u1", planCode: "missing" } }), "evt_retry");
      await expect(deliver(evt)).rejects.toMatchObject({ code: "plan_not_found" });
      mem.state.plans.push({ id: "p-m", kind: "coin_pack", code: "missing", name: "x", priceCents: 1, currency: "EUR", coins: 7, stripePriceId: null });
      expect((await deliver(evt)).status).toBe("processed");
      expect(mem.state.balances.get("u1")).toBe(7);
    });
  });

  describe("subscriptions", () => {
    const invoice = (o: Record<string, unknown> = {}) => ({
      id: "in_1",
      object: "invoice",
      amount_paid: 499,
      currency: "eur",
      customer: "cus_1",
      parent: { type: "subscription_details", subscription_details: { subscription: "sub_123", metadata: {} } },
      ...o,
    });

    it("invoice.paid activates the subscription with the Stripe period", async () => {
      await deliver(event("invoice.paid", invoice()));
      expect(stripe.subscriptions.retrieve).toHaveBeenCalledWith("sub_123");
      expect(mem.state.subs).toEqual([
        expect.objectContaining({ userId: "u1", provider: "stripe", providerSubscriptionId: "sub_123", status: "active", currentPeriodEnd: PERIOD_END }),
      ]);
      expect(mem.state.payments).toEqual([expect.objectContaining({ kind: "subscription", providerRef: "in_1", amountCents: 499 })]);
    });

    it("supports the legacy invoice.subscription field", async () => {
      await deliver(event("invoice.paid", invoice({ parent: null, subscription: "sub_123" })));
      expect(mem.state.subs).toHaveLength(1);
    });

    it("duplicate invoice.paid does not double-record revenue", async () => {
      const evt = event("invoice.paid", invoice(), "evt_inv_dup");
      await deliver(evt);
      await deliver(evt);
      await deliver(event("invoice.paid", invoice())); // different event id, same invoice
      expect(mem.state.payments).toHaveLength(1);
      expect(mem.state.subs).toHaveLength(1);
    });

    it("renewal invoice extends the period and records a new payment", async () => {
      await deliver(event("invoice.paid", invoice()));
      const nextEnd = new Date(PERIOD_END.getTime() + 30 * DAY);
      vi.mocked(stripe.subscriptions.retrieve).mockResolvedValueOnce(
        fakeSubscription({ items: { data: [{ current_period_start: sec(PERIOD_END), current_period_end: sec(nextEnd) }] } }) as never,
      );
      await deliver(event("invoice.paid", invoice({ id: "in_2" })));
      expect(mem.state.subs[0].currentPeriodEnd).toEqual(nextEnd);
      expect(mem.state.payments).toHaveLength(2);
    });

    it("customer.subscription.updated reflects cancel_at_period_end and status", async () => {
      await deliver(event("invoice.paid", invoice()));
      await deliver(event("customer.subscription.updated", fakeSubscription({ cancel_at_period_end: true })));
      expect(mem.state.subs[0]).toMatchObject({ status: "active", cancelAtPeriodEnd: true });
      await deliver(event("customer.subscription.updated", fakeSubscription({ status: "past_due" })));
      expect(mem.state.subs[0].status).toBe("past_due");
    });

    it("invoice.payment_failed marks past_due; subscription.deleted removes access", async () => {
      await deliver(event("invoice.paid", invoice()));
      await deliver(event("invoice.payment_failed", invoice({ id: "in_f" })));
      expect(mem.state.subs[0].status).toBe("past_due");
      await deliver(event("customer.subscription.deleted", fakeSubscription({ status: "canceled" })));
      expect(mem.state.subs[0].status).toBe("expired");
      expect(await mem.repo.findActiveSubscription("u1", NOW)).toBeNull();
    });

    it("subscription checkout completion itself grants nothing (invoice.paid does)", async () => {
      const res = await deliver(
        event("checkout.session.completed", {
          id: "cs_sub",
          mode: "subscription",
          payment_status: "paid",
          customer: "cus_9",
          client_reference_id: "u1",
          metadata: { kind: "subscription", userId: "u1", planCode: "monthly" },
        }),
      );
      expect(res.status).toBe("ignored");
      expect(mem.state.subs).toHaveLength(0);
      expect(mem.state.customers.get("stripe:u1")).toBe("cus_9");
    });
  });

  it("unknown event types are acknowledged and ignored", async () => {
    expect((await deliver(event("payout.paid", { id: "po_1" }))).status).toBe("ignored");
  });

  it("maps Stripe statuses", () => {
    expect(mapStripeStatus("trialing")).toBe("active");
    expect(mapStripeStatus("unpaid")).toBe("past_due");
    expect(mapStripeStatus("incomplete_expired")).toBe("expired");
    expect(mapStripeStatus("incomplete")).toBeNull();
  });
});

describe("StripePaymentProvider API calls (stubbed)", () => {
  it("creates checkout sessions with metadata used by the webhook", async () => {
    const mem = createMemoryRepository();
    const stripe = new Stripe("sk_test_fake");
    const create = vi.spyOn(stripe.checkout.sessions, "create").mockResolvedValue({ url: "https://checkout.stripe.test/x" } as never);
    vi.spyOn(stripe.customers, "create").mockResolvedValue({ id: "cus_new" } as never);
    const provider = new StripePaymentProvider({
      service: createPaymentService(mem.repo),
      repo: mem.repo,
      config: { secretKey: "sk", webhookSecret: SECRET, priceIds: { coins_120: "price_env_120" } },
      stripeFactory: async () => stripe,
    });
    const r = { userId: "u1", email: "u1@kadar.test", successUrl: "https://a/s", cancelUrl: "https://a/c" };
    expect(await provider.createCoinCheckout({ ...r, planCode: "coins_120" })).toEqual({ url: "https://checkout.stripe.test/x" });
    expect(create.mock.calls[0][0]).toMatchObject({
      mode: "payment",
      customer: "cus_new",
      line_items: [{ price: "price_env_120", quantity: 1 }], // env override wins
      metadata: { kind: "coins", userId: "u1", planCode: "coins_120" },
    });
    await provider.createSubscriptionCheckout({ ...r, planCode: "monthly" });
    expect(create.mock.calls[1][0]).toMatchObject({
      mode: "subscription",
      customer: "cus_new", // reused, not created again
      line_items: [{ price: "price_sub", quantity: 1 }], // from pricing_plans
      subscription_data: { metadata: { userId: "u1", planCode: "monthly" } },
    });
    expect(stripe.customers.create).toHaveBeenCalledTimes(1);
  });

  it("billing portal requires a known customer", async () => {
    const mem = createMemoryRepository();
    const stripe = new Stripe("sk_test_fake");
    vi.spyOn(stripe.billingPortal.sessions, "create").mockResolvedValue({ url: "https://portal" } as never);
    const provider = new StripePaymentProvider({
      service: createPaymentService(mem.repo),
      repo: mem.repo,
      config: { secretKey: "sk", webhookSecret: SECRET, priceIds: {} },
      stripeFactory: async () => stripe,
    });
    await expect(provider.openBillingPortal({ userId: "u1", returnUrl: "x" })).rejects.toMatchObject({ code: "no_customer" });
    await mem.repo.saveCustomerId("u1", "stripe", "cus_1");
    expect(await provider.openBillingPortal({ userId: "u1", returnUrl: "x" })).toEqual({ url: "https://portal" });
  });

  it("config from env requires keys only in stripe mode", () => {
    expect(() => stripeConfigFromEnv({} as NodeJS.ProcessEnv)).toThrow(/STRIPE_SECRET_KEY/);
    expect(stripeConfigFromEnv({ STRIPE_SECRET_KEY: "sk", STRIPE_WEBHOOK_SECRET: "wh", STRIPE_PRICE_ID_SUBSCRIPTION: "p" } as never).priceIds.monthly).toBe("p");
  });
});
