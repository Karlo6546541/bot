import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { requireViewer } from "@/lib/auth/session";
import { isMockPayments } from "@/lib/payments";
import { decodeSession } from "@/lib/payments/mock/provider";
import { createClient } from "@/lib/supabase/server";
import { formatMoney } from "@/lib/format";
import { completeMockCheckout } from "@/app/payments/actions";

export const metadata = { robots: { index: false } };

export default async function MockCheckoutPage({ searchParams }: { searchParams: Promise<{ session?: string }> }) {
  if (!isMockPayments()) notFound();
  const { session = "" } = await searchParams;
  const viewer = await requireViewer(`/checkout/mock?session=${session}`);
  const { t, locale } = await getI18n();
  let s;
  try {
    s = decodeSession(session);
    if (s.userId !== viewer.id) throw new Error();
  } catch {
    return <p role="alert" className="py-16 text-center">{t("checkout.invalidSession")}</p>;
  }
  const supabase = await createClient();
  const { data: plan } = await supabase.from("pricing_plans").select("*").eq("code", s.planCode).single();
  if (!plan) notFound();

  return (
    <section className="mx-auto max-w-md space-y-6 py-6" aria-labelledby="mock-title">
      <div className="rounded-lg border-2 border-dashed border-amber-500 p-3 text-sm text-amber-900 dark:text-amber-200">
        {t("checkout.mockText")}
      </div>
      <h1 id="mock-title" className="h1">{t("checkout.mockTitle")}</h1>
      <dl className="card grid grid-cols-2 gap-2">
        <dt className="muted">{t("checkout.item")}</dt>
        <dd className="text-right font-semibold">{plan.name}</dd>
        <dt className="muted">{t("checkout.amount")}</dt>
        <dd className="text-right font-semibold">{formatMoney(plan.price_cents, plan.currency, locale)}</dd>
      </dl>
      <form action={completeMockCheckout} className="grid gap-3">
        <input type="hidden" name="session" value={session} />
        <button name="outcome" value="success" className="btn-primary">{t("checkout.simulateSuccess")}</button>
        <button name="outcome" value="failure" className="btn-secondary">{t("checkout.simulateFailure")}</button>
      </form>
    </section>
  );
}
