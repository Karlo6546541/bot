import "server-only";
import { env } from "@/lib/env";
import { createPaymentService, type PaymentService } from "./service";
import { createSupabasePaymentRepository } from "./supabaseRepository";
import type { PaymentProvider, PaymentRepository } from "./types";
import type { MockPaymentProvider } from "./mock/provider";

let shared: { repo: PaymentRepository; service: PaymentService } | null = null;

/** The shared payment service (business logic), backed by Supabase. */
export function getPaymentService() {
  if (!shared) {
    const repo = createSupabasePaymentRepository();
    shared = { repo, service: createPaymentService(repo) };
  }
  return shared;
}

/**
 * Provider selected by PAYMENT_PROVIDER (default "mock").
 * Both providers are loaded with dynamic import, so the Stripe module (and SDK)
 * is never evaluated in mock mode.
 */
export async function getPaymentProvider(): Promise<PaymentProvider> {
  const { repo, service } = getPaymentService();
  if (env.paymentProvider === "stripe") {
    const { StripePaymentProvider, stripeConfigFromEnv } = await import("./stripe/provider");
    return new StripePaymentProvider({ service, repo, config: stripeConfigFromEnv() });
  }
  const { MockPaymentProvider } = await import("./mock/provider");
  return new MockPaymentProvider({ service, repo });
}

/** Mock-only helpers (checkout simulation, expire/renew). Null when using Stripe. */
export async function getMockProvider(): Promise<MockPaymentProvider | null> {
  if (env.paymentProvider !== "mock") return null;
  return (await getPaymentProvider()) as MockPaymentProvider;
}

export function isMockPayments() {
  return env.paymentProvider === "mock";
}
