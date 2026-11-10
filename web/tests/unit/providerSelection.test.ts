import { afterEach, describe, expect, it, vi } from "vitest";

describe("getPaymentProvider", () => {
  afterEach(() => {
    vi.resetModules();
    vi.doUnmock("stripe");
  });

  it("mock mode works with NO Stripe env vars and never loads the Stripe SDK", async () => {
    vi.stubEnv("PAYMENT_PROVIDER", "mock");
    vi.stubEnv("STRIPE_SECRET_KEY", "");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "test");
    const loaded = vi.fn();
    vi.doMock("stripe", () => {
      loaded();
      throw new Error("Stripe SDK must not be loaded in mock mode");
    });
    const { getPaymentProvider } = await import("@/lib/payments");
    const provider = await getPaymentProvider();
    expect(provider.name).toBe("mock");
    expect(loaded).not.toHaveBeenCalled();
  });

  it("stripe mode fails fast with a clear error when keys are missing", async () => {
    vi.stubEnv("PAYMENT_PROVIDER", "stripe");
    vi.stubEnv("STRIPE_SECRET_KEY", "");
    vi.stubEnv("STRIPE_WEBHOOK_SECRET", "");
    vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "test");
    const { getPaymentProvider } = await import("@/lib/payments");
    await expect(getPaymentProvider()).rejects.toMatchObject({ code: "misconfigured" });
  });

  it("stripe mode returns the Stripe provider when configured", async () => {
    vi.stubEnv("PAYMENT_PROVIDER", "stripe");
    vi.stubEnv("STRIPE_SECRET_KEY", "sk_test_x");
    vi.stubEnv("STRIPE_WEBHOOK_SECRET", "whsec_x");
    vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "test");
    const { getPaymentProvider } = await import("@/lib/payments");
    expect((await getPaymentProvider()).name).toBe("stripe");
  });
});
