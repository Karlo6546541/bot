import { NextResponse } from "next/server";
import { env } from "@/lib/env";
import { getPaymentProvider } from "@/lib/payments";
import { PaymentError } from "@/lib/payments/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Stripe webhook endpoint. Only active when PAYMENT_PROVIDER=stripe.
 * - 400 on bad signature (Stripe will not retry)
 * - 500 on processing errors (claim released, Stripe retries)
 * - 200 for processed / duplicate / ignored events
 */
export async function POST(req: Request) {
  if (env.paymentProvider !== "stripe") return new NextResponse("Not found", { status: 404 });
  const rawBody = await req.text(); // raw body is required for signature verification
  try {
    const provider = await getPaymentProvider();
    const result = await provider.handleWebhookEvent({ rawBody, signature: req.headers.get("stripe-signature") });
    return NextResponse.json({ received: true, ...result });
  } catch (err) {
    if (err instanceof PaymentError && err.code === "invalid_signature") {
      return NextResponse.json({ error: "invalid_signature" }, { status: 400 });
    }
    console.error("[stripe webhook]", err);
    return NextResponse.json({ error: "processing_failed" }, { status: 500 });
  }
}
