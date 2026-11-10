import { getI18n } from "@/lib/i18n/server";
import { requireAdmin } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { formatMoney, periodOf } from "@/lib/format";

export default async function AdminStats() {
  await requireAdmin();
  const { t, locale } = await getI18n();
  const db = createAdminClient();
  const now = new Date();
  const period = periodOf(now);
  const monthStart = new Date(`${period}T00:00:00Z`).toISOString();
  const count = (q: PromiseLike<{ count: number | null }>) => Promise.resolve(q).then((r) => r.count ?? 0);
  const [users, creators, series, subs, revenue, coins, unlocks, earnings] = await Promise.all([
    count(db.from("profiles").select("id", { count: "exact", head: true })),
    count(db.from("creators").select("id", { count: "exact", head: true }).eq("status", "approved")),
    count(db.from("series").select("id", { count: "exact", head: true }).eq("status", "published").eq("hidden_by_admin", false)),
    count(db.from("subscriptions").select("id", { count: "exact", head: true }).eq("status", "active").gt("current_period_end", now.toISOString())),
    Promise.all([
      db.rpc("sum_payments", { p_period: period, p_kind: "subscription" }),
      db.rpc("sum_payments", { p_period: period, p_kind: "coin_pack" }),
    ]).then(([a, b]) => Number(a.data ?? 0) + Number(b.data ?? 0)),
    db.from("coin_transactions").select("amount").eq("type", "purchase").gte("created_at", monthStart)
      .then((r) => (r.data ?? []).reduce((s, x) => s + x.amount, 0)),
    count(db.from("chapter_unlocks").select("chapter_id", { count: "exact", head: true }).gte("created_at", monthStart)),
    db.rpc("earnings_summary", {}).then((r) =>
      (r.data ?? []).filter((x) => x.period === period).reduce((s, x) => s + Number(x.creator_cents), 0),
    ),
  ]);
  const stats: [string, string | number][] = [
    [t("admin.users"), users],
    [t("admin.creators"), creators],
    [t("admin.series"), series],
    [t("admin.activeSubs"), subs],
    [t("admin.revenueMonth"), formatMoney(revenue, "EUR", locale)],
    [t("admin.coinsSold"), coins],
    [t("admin.unlocksMonth"), unlocks],
    [t("creator.earnings"), formatMoney(earnings, "EUR", locale)],
  ];
  return (
    <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {stats.map(([label, value]) => (
        <div key={label} className="card">
          <dt className="muted text-xs">{label}</dt>
          <dd className="mt-1 text-2xl font-black tabular-nums">{value}</dd>
        </div>
      ))}
    </dl>
  );
}
