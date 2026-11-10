import type { Metadata } from "next";
import { getI18n } from "@/lib/i18n/server";
import { createClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth/session";
import { formatMoney } from "@/lib/format";
import { monetizationDefaults } from "@/config/monetization";
import { startCoinCheckout, startSubscriptionCheckout } from "@/app/payments/actions";
import { PaymentErrorNotice } from "@/components/payments/PaymentErrorNotice";
import { CoinIcon } from "@/components/ui/Icons";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("pricing.title") };
}

export default async function PricingPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { t, locale } = await getI18n();
  const { error } = await searchParams;
  const supabase = await createClient();
  const viewer = await getViewer();
  const [{ data: plans }, { data: share }, sub] = await Promise.all([
    supabase.from("pricing_plans").select("*").eq("active", true).order("sort"),
    supabase.from("platform_settings").select("value").eq("key", "creator_share_pct").maybeSingle(),
    viewer
      ? supabase
          .from("subscriptions")
          .select("id")
          .eq("user_id", viewer.id)
          .eq("status", "active")
          .gt("current_period_end", new Date().toISOString())
          .limit(1)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  const subPlan = plans?.find((p) => p.kind === "subscription");
  const packs = plans?.filter((p) => p.kind === "coin_pack") ?? [];
  const sharePct = Number(share?.value ?? monetizationDefaults.creatorSharePct);

  return (
    <div className="space-y-10">
      <h1 className="h1">{t("pricing.title")}</h1>
      <PaymentErrorNotice code={error} />

      {subPlan && (
        <section aria-labelledby="sub" className="card !bg-sun !text-ink-900 sm:p-6">
          <h2 id="sub" className="h2">{t("pricing.subscriptionTitle")}</h2>
          <p className="mt-1 font-medium">{t("pricing.subscriptionText")}</p>
          <p className="mt-4 text-4xl font-black" style={{ fontFamily: "var(--font-display)" }}>
            {t("pricing.perMonth", { price: formatMoney(subPlan.price_cents, subPlan.currency, locale) })}
          </p>
          {sub.data ? (
            <p className="mt-4 font-semibold text-emerald-700 dark:text-emerald-400">✓ {t("pricing.alreadySubscribed")}</p>
          ) : (
            <form action={startSubscriptionCheckout} className="mt-4">
              <input type="hidden" name="planCode" value={subPlan.code} />
              <button className="btn-primary w-full sm:w-auto">{t("pricing.subscribe")}</button>
            </form>
          )}
          <p className="muted mt-3 text-xs">{t("pricing.creatorShare", { pct: sharePct })}</p>
        </section>
      )}

      <section aria-labelledby="coins" id="coins" className="scroll-mt-20">
        <h2 id="coins-title" className="h2">{t("pricing.coinsTitle")}</h2>
        <p className="muted mt-1">{t("pricing.coinsText")}</p>
        <ul className="mt-4 grid gap-3 sm:grid-cols-3">
          {packs.map((p) => (
            <li key={p.id} className="card flex flex-col gap-3">
              <p className="flex items-center gap-2 text-xl font-black"><CoinIcon className="h-7 w-7 text-brand-600" /> {t("common.coinCount", { count: p.coins ?? 0 })}</p>
              <p className="text-lg">{formatMoney(p.price_cents, p.currency, locale)}</p>
              <form action={startCoinCheckout} className="mt-auto">
                <input type="hidden" name="planCode" value={p.code} />
                <button className="btn-secondary w-full">{t("pricing.buy")}</button>
              </form>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
