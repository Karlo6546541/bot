/**
 * StripePaymentProvider (PAYMENT_PROVIDER=stripe).
 *
 * - The Stripe SDK is imported lazily (dynamic import) on first use, so the
 *   app never loads or needs it in mock mode.
 * - Webhooks: signature verified with STRIPE_WEBHOOK_SECRET, processed once
 *   per event id (processed_payment_events) via the shared PaymentService.
 */
import type Stripe from "stripe";
import type { PaymentService } from "../service";
import {
  PaymentError,
  type CheckoutRequest,
  type PaymentProvider,
  type PaymentRepository,
  type Plan,
  type RedirectResult,
  type SubscriptionStatus,
  type WebhookInput,
  type WebhookResult,
} from "../types";

export interface StripeConfig {
  secretKey: string;
  webhookSecret: string;
  /** Env overrides keyed by plan code (e.g. monthly, coins_50). Falls back to pricing_plans.stripe_price_id. */
  priceIds: Record<string, string | undefined>;
}

export function stripeConfigFromEnv(env: NodeJS.ProcessEnv = process.env): StripeConfig {
  const secretKey = env.STRIPE_SECRET_KEY;
  const webhookSecret = env.STRIPE_WEBHOOK_SECRET;
  if (!secretKey || !webhookSecret) {
    throw new PaymentError("misconfigured", "PAYMENT_PROVIDER=stripe requires STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET");
  }
  return {
    secretKey,
    webhookSecret,
    priceIds: {
      monthly: env.STRIPE_PRICE_ID_SUBSCRIPTION,
      coins_50: env.STRIPE_PRICE_ID_COINS_50,
      coins_120: env.STRIPE_PRICE_ID_COINS_120,
      coins_300: env.STRIPE_PRICE_ID_COINS_300,
    },
  };
}

export type StripeFactory = (secretKey: string) => Promise<Stripe>;

const defaultFactory: StripeFactory = async (key) => {
  const { default: StripeCtor } = await import("stripe");
  return new StripeCtor(key, { appInfo: { name: "Kadar" }, maxNetworkRetries: 2 });
};

/** Map Stripe subscription statuses to ours. null = do not touch the record. */
export function mapStripeStatus(s: Stripe.Subscription.Status): SubscriptionStatus | null {
  switch (s) {
    case "active":
    case "trialing":
      return "active";
    case "past_due":
    case "unpaid":
      return "past_due";
    case "canceled":
      return "canceled";
    case "incomplete_expired":
      return "expired";
    default:
      return null; // incomplete, paused
  }
}

const idOf = (v: string | { id: string } | null | undefined) => (typeof v === "string" ? v : (v?.id ?? null));

/** Period lives on subscription items in current API versions; fall back to legacy top-level fields. */
export function subscriptionPeriod(sub: Stripe.Subscription): { start: Date; end: Date } {
  const item = sub.items?.data?.[0] as (Stripe.SubscriptionItem & Record<string, unknown>) | undefined;
  const legacy = sub as unknown as { current_period_start?: number; current_period_end?: number };
  const start = item?.current_period_start ?? legacy.current_period_start ?? sub.start_date;
  const end = item?.current_period_end ?? legacy.current_period_end ?? start;
  return { start: new Date(start * 1000), end: new Date(end * 1000) };
}

function invoiceSubscriptionId(inv: Stripe.Invoice): string | null {
  const parent = (inv as unknown as { parent?: { subscription_details?: { subscription?: string | { id: string } } } })
    .parent;
  const legacy = (inv as unknown as { subscription?: string | { id: string } }).subscription;
  return idOf(parent?.subscription_details?.subscription ?? legacy ?? null);
}

export class StripePaymentProvider implements PaymentProvider {
  readonly name = "stripe" as const;
  private client: Promise<Stripe> | null = null;

  constructor(
    private readonly deps: {
      service: PaymentService;
      repo: PaymentRepository;
      config: StripeConfig;
      stripeFactory?: StripeFactory;
    },
  ) {}

  private stripe(): Promise<Stripe> {
    this.client ??= (this.deps.stripeFactory ?? defaultFactory)(this.deps.config.secretKey);
    return this.client;
  }

  private async priceFor(planCode: string, kind: Plan["kind"]): Promise<{ plan: Plan; priceId: string }> {
    const plan = await this.deps.repo.getPlanByCode(planCode);
    if (!plan || plan.kind !== kind) throw new PaymentError("plan_not_found", planCode);
    const priceId = this.deps.config.priceIds[plan.code] ?? plan.stripePriceId;
    if (!priceId) throw new PaymentError("misconfigured", `No Stripe price id for plan ${plan.code}`);
    return { plan, priceId };
  }

  private async customerFor(userId: string, email: string): Promise<string> {
    const existing = await this.deps.repo.getCustomerId(userId, "stripe");
    if (existing) return existing;
    const stripe = await this.stripe();
    const customer = await stripe.customers.create(
      { email, metadata: { userId } },
      { idempotencyKey: `customer:${userId}` },
    );
    await this.deps.repo.saveCustomerId(userId, "stripe", customer.id);
    return customer.id;
  }

  async createSubscriptionCheckout(req: CheckoutRequest): Promise<RedirectResult> {
    if (await this.deps.service.findActiveSubscription(req.userId)) throw new PaymentError("already_subscribed");
    const { plan, priceId } = await this.priceFor(req.planCode, "subscription");
    const stripe = await this.stripe();
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: await this.customerFor(req.userId, req.email),
      client_reference_id: req.userId,
      line_items: [{ price: priceId, quantity: 1 }],
      metadata: { kind: "subscription", userId: req.userId, planCode: plan.code },
      subscription_data: { metadata: { userId: req.userId, planCode: plan.code } },
      success_url: req.successUrl,
      cancel_url: req.cancelUrl,
      locale: "hr",
    });
    if (!session.url) throw new Error("Stripe did not return a checkout URL");
    return { url: session.url };
  }

  async createCoinCheckout(req: CheckoutRequest): Promise<RedirectResult> {
    const { plan, priceId } = await this.priceFor(req.planCode, "coin_pack");
    const stripe = await this.stripe();
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer: await this.customerFor(req.userId, req.email),
      client_reference_id: req.userId,
      line_items: [{ price: priceId, quantity: 1 }],
      metadata: { kind: "coins", userId: req.userId, planCode: plan.code },
      payment_intent_data: { metadata: { kind: "coins", userId: req.userId, planCode: plan.code } },
      success_url: req.successUrl,
      cancel_url: req.cancelUrl,
      locale: "hr",
    });
    if (!session.url) throw new Error("Stripe did not return a checkout URL");
    return { url: session.url };
  }

  async openBillingPortal({ userId, returnUrl }: { userId: string; returnUrl: string }): Promise<RedirectResult> {
    const customer = await this.deps.repo.getCustomerId(userId, "stripe");
    if (!customer) throw new PaymentError("no_customer");
    const stripe = await this.stripe();
    const portal = await stripe.billingPortal.sessions.create({ customer, return_url: returnUrl });
    return { url: portal.url };
  }

  async cancelSubscription({ userId }: { userId: string }): Promise<void> {
    const sub = await this.deps.service.findActiveSubscription(userId);
    if (!sub || sub.provider !== "stripe") throw new PaymentError("no_subscription");
    const stripe = await this.stripe();
    await stripe.subscriptions.update(sub.providerSubscriptionId, { cancel_at_period_end: true });
    // Reflect immediately; customer.subscription.updated will confirm it.
    await this.deps.service.scheduleCancellation(sub.providerSubscriptionId);
  }

  async handleWebhookEvent({ rawBody, signature }: WebhookInput): Promise<WebhookResult> {
    if (!signature) throw new PaymentError("invalid_signature", "Missing Stripe-Signature header");
    const stripe = await this.stripe();
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(rawBody, signature, this.deps.config.webhookSecret);
    } catch (err) {
      throw new PaymentError("invalid_signature", (err as Error).message);
    }
    const out = await this.deps.service.processEventOnce("stripe", event.id, event.type, () => this.dispatch(event));
    return { status: out.duplicate ? "duplicate" : out.result, eventId: event.id, type: event.type };
  }

  private async dispatch(event: Stripe.Event): Promise<"processed" | "ignored"> {
    const { service, repo } = this.deps;
    switch (event.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded": {
        const s = event.data.object;
        const userId = s.metadata?.userId ?? s.client_reference_id;
        if (!userId) return "ignored";
        const customer = idOf(s.customer);
        if (customer) await repo.saveCustomerId(userId, "stripe", customer);
        if (s.metadata?.kind === "coins") {
          if (s.payment_status !== "paid") return "ignored"; // async methods: wait for async_payment_succeeded
          await service.creditCoinPurchase({
            userId,
            packCode: s.metadata.planCode,
            provider: "stripe",
            paymentRef: idOf(s.payment_intent) ?? s.id,
            amountCents: s.amount_total ?? undefined,
            currency: s.currency ?? undefined,
          });
          return "processed";
        }
        // Subscriptions are activated by invoice.paid (also covers renewals).
        return "ignored";
      }

      case "invoice.paid": {
        const invoice = event.data.object;
        const subId = invoiceSubscriptionId(invoice);
        if (!subId) return "ignored";
        const stripe = await this.stripe();
        const sub = await stripe.subscriptions.retrieve(subId);
        const userId = sub.metadata?.userId ?? (await repo.findSubscriptionByProviderId(sub.id))?.userId;
        if (!userId) throw new Error(`Cannot resolve user for Stripe subscription ${sub.id}`);
        const { start, end } = subscriptionPeriod(sub);
        await service.activateSubscription({
          userId,
          planCode: sub.metadata?.planCode ?? "monthly",
          provider: "stripe",
          providerSubscriptionId: sub.id,
          providerCustomerId: idOf(sub.customer),
          periodStart: start,
          periodEnd: end,
          cancelAtPeriodEnd: sub.cancel_at_period_end,
          payment: { ref: invoice.id ?? `inv_${event.id}`, amountCents: invoice.amount_paid, currency: invoice.currency },
        });
        return "processed";
      }

      case "invoice.payment_failed": {
        const subId = invoiceSubscriptionId(event.data.object);
        if (!subId) return "ignored";
        await service.setSubscriptionStatus(subId, { status: "past_due" });
        return "processed";
      }

      case "customer.subscription.created":
      case "customer.subscription.updated": {
        const sub = event.data.object;
        const status = mapStripeStatus(sub.status);
        if (!status) return "ignored";
        const { start, end } = subscriptionPeriod(sub);
        const existing = await repo.findSubscriptionByProviderId(sub.id);
        if (!existing) {
          // Not activated yet (invoice.paid pending) — only create it if it is active.
          if (status !== "active" || !sub.metadata?.userId) return "ignored";
          await service.activateSubscription({
            userId: sub.metadata.userId,
            planCode: sub.metadata.planCode ?? "monthly",
            provider: "stripe",
            providerSubscriptionId: sub.id,
            providerCustomerId: idOf(sub.customer),
            periodStart: start,
            periodEnd: end,
            cancelAtPeriodEnd: sub.cancel_at_period_end,
          });
          return "processed";
        }
        await service.setSubscriptionStatus(sub.id, {
          status,
          cancelAtPeriodEnd: sub.cancel_at_period_end,
          periodStart: start,
          periodEnd: end,
        });
        return "processed";
      }

      case "customer.subscription.deleted": {
        await service.expireSubscription(event.data.object.id);
        return "processed";
      }

      default:
        return "ignored";
    }
  }
}
