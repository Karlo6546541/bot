/**
 * MockPaymentProvider — the default (PAYMENT_PROVIDER=mock).
 * Makes NO external calls. "Checkout" is the internal page /checkout/mock;
 * its buttons produce synthetic events that go through handleWebhookEvent and
 * the shared PaymentService, writing exactly the records a real payment would.
 */
import { monetizationDefaults } from "@/config/monetization";
import type { PaymentService } from "../service";
import {
  PaymentError,
  type CheckoutRequest,
  type PaymentProvider,
  type PaymentRepository,
  type RedirectResult,
  type WebhookInput,
  type WebhookResult,
} from "../types";

const DAY = 86_400_000;

export interface MockSession {
  sid: string;
  kind: "subscription" | "coins";
  planCode: string;
  userId: string;
  successUrl: string;
  cancelUrl: string;
  iat: number;
}

export type MockEvent =
  | { id: string; type: "checkout.succeeded"; session: MockSession }
  | { id: string; type: "checkout.failed"; session: MockSession }
  | { id: string; type: "subscription.canceled"; userId: string }
  | { id: string; type: "subscription.expired"; userId: string }
  | { id: string; type: "subscription.renewed"; userId: string };

const SESSION_TTL_MS = 60 * 60 * 1000;

export function encodeSession(s: MockSession): string {
  return Buffer.from(JSON.stringify(s)).toString("base64url");
}

export function decodeSession(token: string, now = Date.now()): MockSession {
  try {
    const s = JSON.parse(Buffer.from(token, "base64url").toString("utf8")) as MockSession;
    if (!s.sid || !s.userId || !s.planCode || (s.kind !== "subscription" && s.kind !== "coins")) throw new Error();
    if (now - s.iat > SESSION_TTL_MS) throw new Error();
    return s;
  } catch {
    throw new PaymentError("invalid_session");
  }
}

const relativeOnly = (u: string) => {
  try {
    const url = new URL(u, "http://x");
    return url.pathname + url.search;
  } catch {
    return "/";
  }
};

export class MockPaymentProvider implements PaymentProvider {
  readonly name = "mock" as const;

  constructor(
    private readonly deps: {
      service: PaymentService;
      repo: PaymentRepository;
      clock?: () => Date;
      newId?: () => string;
    },
  ) {}

  private now() {
    return this.deps.clock?.() ?? new Date();
  }
  private id() {
    return this.deps.newId?.() ?? crypto.randomUUID();
  }

  private async checkout(kind: MockSession["kind"], req: CheckoutRequest): Promise<RedirectResult> {
    const plan = await this.deps.repo.getPlanByCode(req.planCode);
    const expected = kind === "subscription" ? "subscription" : "coin_pack";
    if (!plan || plan.kind !== expected) throw new PaymentError("plan_not_found", req.planCode);
    if (kind === "subscription" && (await this.deps.service.findActiveSubscription(req.userId))) {
      throw new PaymentError("already_subscribed");
    }
    const session: MockSession = {
      sid: this.id(),
      kind,
      planCode: plan.code,
      userId: req.userId,
      successUrl: relativeOnly(req.successUrl),
      cancelUrl: relativeOnly(req.cancelUrl),
      iat: this.now().getTime(),
    };
    return { url: `/checkout/mock?session=${encodeSession(session)}` };
  }

  createSubscriptionCheckout(req: CheckoutRequest) {
    return this.checkout("subscription", req);
  }

  createCoinCheckout(req: CheckoutRequest) {
    return this.checkout("coins", req);
  }

  async openBillingPortal(_req: { userId: string; returnUrl: string }): Promise<RedirectResult> {
    // No external portal in mock mode: the account page has the simulated actions.
    return { url: "/account#subscription" };
  }

  async cancelSubscription({ userId }: { userId: string }) {
    await this.handle({ id: `mock_evt_${this.id()}`, type: "subscription.canceled", userId });
  }

  // --- mock-only helpers used by the checkout page and test tools ----------
  async completeCheckout(token: string, outcome: "success" | "failure", viewerId: string) {
    const session = decodeSession(token, this.now().getTime());
    if (session.userId !== viewerId) throw new PaymentError("invalid_session");
    // Event id is derived from the session: clicking twice cannot double-charge.
    return this.handle({
      id: `mock_evt_${session.sid}`,
      type: outcome === "success" ? "checkout.succeeded" : "checkout.failed",
      session,
    });
  }

  simulateExpire(userId: string) {
    return this.handle({ id: `mock_evt_${this.id()}`, type: "subscription.expired", userId });
  }

  simulateRenew(userId: string) {
    return this.handle({ id: `mock_evt_${this.id()}`, type: "subscription.renewed", userId });
  }

  /** Mock events are never accepted over HTTP; only trusted server code calls this. */
  async handleWebhookEvent(input: WebhookInput): Promise<WebhookResult> {
    return this.handle(JSON.parse(input.rawBody) as MockEvent);
  }

  private async handle(event: MockEvent): Promise<WebhookResult> {
    const { service } = this.deps;
    const out = await service.processEventOnce("mock", event.id, event.type, () => this.dispatch(event));
    return { status: out.duplicate ? "duplicate" : out.result, eventId: event.id, type: event.type };
  }

  private async dispatch(event: MockEvent): Promise<"processed" | "ignored"> {
    const { service, repo } = this.deps;
    const now = this.now();
    switch (event.type) {
      case "checkout.failed":
        return "processed"; // nothing is granted
      case "checkout.succeeded": {
        const s = event.session;
        const plan = await repo.getPlanByCode(s.planCode);
        if (!plan) throw new PaymentError("plan_not_found", s.planCode);
        if (s.kind === "coins") {
          await service.creditCoinPurchase({
            userId: s.userId,
            packCode: s.planCode,
            provider: "mock",
            paymentRef: `mock_pay_${s.sid}`,
            amountCents: plan.priceCents,
            currency: plan.currency,
          });
        } else {
          await service.activateSubscription({
            userId: s.userId,
            planCode: s.planCode,
            provider: "mock",
            providerSubscriptionId: `mock_sub_${s.sid}`,
            providerCustomerId: `mock_cus_${s.userId}`,
            periodStart: now,
            periodEnd: new Date(now.getTime() + monetizationDefaults.subscriptionPeriodDays * DAY),
            payment: { ref: `mock_pay_${s.sid}`, amountCents: plan.priceCents, currency: plan.currency },
          });
        }
        return "processed";
      }
      case "subscription.canceled": {
        const sub = await service.findActiveSubscription(event.userId);
        if (!sub) throw new PaymentError("no_subscription");
        await service.scheduleCancellation(sub.providerSubscriptionId);
        return "processed";
      }
      case "subscription.expired": {
        const sub = await service.findActiveSubscription(event.userId);
        if (!sub) throw new PaymentError("no_subscription");
        await service.expireSubscription(sub.providerSubscriptionId);
        return "processed";
      }
      case "subscription.renewed": {
        const sub = await service.findActiveSubscription(event.userId);
        if (!sub || sub.cancelAtPeriodEnd) throw new PaymentError("no_subscription");
        const plan = sub.planId ? await repo.getPlanById(sub.planId) : await repo.getPlanByCode("monthly");
        if (!plan) throw new PaymentError("plan_not_found");
        const start = sub.currentPeriodEnd;
        await service.activateSubscription({
          userId: sub.userId,
          planCode: plan.code,
          provider: "mock",
          providerSubscriptionId: sub.providerSubscriptionId,
          providerCustomerId: sub.providerCustomerId,
          periodStart: start,
          periodEnd: new Date(start.getTime() + monetizationDefaults.subscriptionPeriodDays * DAY),
          payment: { ref: `mock_pay_${event.id}`, amountCents: plan.priceCents, currency: plan.currency },
        });
        return "processed";
      }
    }
  }
}
