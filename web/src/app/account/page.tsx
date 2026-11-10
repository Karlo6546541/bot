import type { Metadata } from "next";
import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { requireViewer } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { formatDate, formatDateTime } from "@/lib/format";
import { isMockPayments } from "@/lib/payments";
import {
  cancelSubscriptionAction,
  openBillingPortalAction,
  simulateSubscriptionEvent,
} from "@/app/payments/actions";
import { PaymentErrorNotice } from "@/components/payments/PaymentErrorNotice";
import { ConfirmButton } from "@/components/forms/ConfirmButton";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("account.title") };
}

export default async function AccountPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const viewer = await requireViewer("/account");
  const { t, locale } = await getI18n();
  const { error } = await searchParams;
  const supabase = await createClient();
  const [{ data: subs }, { data: balance }, { data: txs }, { data: creator }] = await Promise.all([
    supabase.from("subscriptions").select("*").eq("user_id", viewer.id).order("current_period_end", { ascending: false }).limit(1),
    supabase.from("coin_balances").select("balance").eq("user_id", viewer.id).maybeSingle(),
    supabase
      .from("coin_transactions")
      .select("id, type, amount, created_at, chapters(number, series(title))")
      .eq("user_id", viewer.id)
      .order("created_at", { ascending: false })
      .limit(10),
    supabase.from("creators").select("status").eq("id", viewer.id).maybeSingle(),
  ]);
  const sub = subs?.[0];
  const active = sub && sub.status === "active" && new Date(sub.current_period_end) > new Date();
  const mock = isMockPayments();

  return (
    <div className="space-y-8">
      <h1 className="h1">{t("account.title")}</h1>
      <PaymentErrorNotice code={error} />

      <section className="card" aria-labelledby="profile">
        <h2 id="profile" className="h2">{t("account.profile")}</h2>
        <p className="mt-2 font-semibold">{viewer.profile.display_name}</p>
        <p className="muted text-sm">{viewer.email}</p>
        {!creator && viewer.profile.role === "reader" && (
          <Link href="/creator/apply" className="btn-secondary mt-3">{t("account.becomeCreator")}</Link>
        )}
      </section>

      <section id="subscription" className="card scroll-mt-20" aria-labelledby="sub-title">
        <h2 id="sub-title" className="h2">{t("account.subscription")}</h2>
        {!sub || !active ? (
          <>
            <p className="muted mt-2">{t("account.noSubscription")}</p>
            {sub && <p className="mt-1 text-sm">{t("account.status")}: {t(`account.statuses.${sub.status}`)}</p>}
            <Link href="/pricing" className="btn-primary mt-3">{t("pricing.subscribe")}</Link>
          </>
        ) : (
          <div className="mt-2 space-y-3">
            <p>
              {sub.cancel_at_period_end
                ? t("account.cancelsAt", { date: formatDate(sub.current_period_end, locale) })
                : t("account.activeUntil", { date: formatDate(sub.current_period_end, locale) })}
            </p>
            <div className="flex flex-wrap gap-2">
              {!sub.cancel_at_period_end && (
                <form action={cancelSubscriptionAction}>
                  <ConfirmButton className="btn-secondary" message={t("account.cancelConfirm")}>
                    {t("account.cancelSubscription")}
                  </ConfirmButton>
                </form>
              )}
              {!mock && (
                <form action={openBillingPortalAction}>
                  <button className="btn-secondary">{t("account.manageBilling")}</button>
                </form>
              )}
            </div>
          </div>
        )}
        {mock && active && (
          <form action={simulateSubscriptionEvent} className="mt-4 flex flex-wrap gap-2 border-t border-dashed border-amber-500 pt-3">
            <p className="w-full text-xs font-semibold text-amber-700 dark:text-amber-400">{t("account.mockTools")}</p>
            <button name="event" value="expire" className="btn-ghost border border-amber-500">{t("account.simulateExpire")}</button>
            {!sub!.cancel_at_period_end && (
              <button name="event" value="renew" className="btn-ghost border border-amber-500">{t("account.simulateRenew")}</button>
            )}
          </form>
        )}
      </section>

      <section className="card" aria-labelledby="coins-title">
        <h2 id="coins-title" className="h2">{t("account.coins")}</h2>
        <p className="mt-2 text-lg font-semibold">🪙 {t("account.balance", { coins: t("common.coinCount", { count: balance?.balance ?? 0 }) })}</p>
        <Link href="/pricing#coins" className="btn-secondary mt-3">{t("reader.buyCoins")}</Link>
        <h3 className="mt-6 font-semibold">{t("account.transactions")}</h3>
        {!txs?.length ? (
          <p className="muted text-sm">{t("account.noTransactions")}</p>
        ) : (
          <table className="table mt-2">
            <tbody>
              {txs.map((tx) => (
                <tr key={tx.id}>
                  <td>
                    {t(`account.txTypes.${tx.type}`)}
                    {tx.chapters && (
                      <span className="muted block text-xs">
                        {tx.chapters.series?.title} #{tx.chapters.number}
                      </span>
                    )}
                  </td>
                  <td className={`text-right font-semibold tabular-nums ${tx.amount > 0 ? "text-emerald-700 dark:text-emerald-400" : ""}`}>
                    {tx.amount > 0 ? `+${tx.amount}` : tx.amount}
                  </td>
                  <td className="muted text-right text-xs">{formatDateTime(tx.created_at, locale)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
