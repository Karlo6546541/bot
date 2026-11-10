import { getI18n } from "@/lib/i18n/server";
import { requireAdmin } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { monetizationDefaults } from "@/config/monetization";
import { ActionForm } from "@/components/creator/ActionForm";
import { distributePool, savePlan, saveSettings } from "../actions";

export default async function AdminSettings() {
  await requireAdmin();
  const { t } = await getI18n();
  const db = createAdminClient();
  const [{ data: settings }, { data: plans }] = await Promise.all([
    db.from("platform_settings").select("key, value"),
    db.from("pricing_plans").select("*").order("sort"),
  ]);
  const get = (k: string, d: number) => Number(settings?.find((s) => s.key === k)?.value ?? d);
  const lastMonth = new Date();
  lastMonth.setUTCMonth(lastMonth.getUTCMonth() - 1);

  return (
    <div className="space-y-8">
      <section className="card space-y-3" aria-labelledby="rev">
        <h2 id="rev" className="h2">{t("admin.settings")}</h2>
        <ActionForm action={saveSettings} submitLabel={t("common.save")} className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="label" htmlFor="creator_share_pct">{t("admin.creatorShare")}</label>
            <input className="input" id="creator_share_pct" name="creator_share_pct" type="number" step="0.01" min={0} max={100}
              defaultValue={get("creator_share_pct", monetizationDefaults.creatorSharePct)} />
          </div>
          <div>
            <label className="label" htmlFor="coin_value_cents">{t("admin.coinValue")}</label>
            <input className="input" id="coin_value_cents" name="coin_value_cents" type="number" min={1}
              defaultValue={get("coin_value_cents", monetizationDefaults.coinValueCents)} />
          </div>
        </ActionForm>
      </section>

      <section className="space-y-3" aria-labelledby="plans">
        <h2 id="plans" className="h2">{t("admin.plans")}</h2>
        {(plans ?? []).map((p) => (
          <div key={p.id} className="card">
            <h3 className="font-semibold">{p.name} <code className="muted text-xs">{p.code}</code></h3>
            <ActionForm action={savePlan.bind(null, p.id)} submitLabel={t("common.save")} className="mt-2 grid gap-3 sm:grid-cols-4">
              <div>
                <label className="label" htmlFor={`price-${p.id}`}>{t("checkout.amount")} (cent)</label>
                <input className="input" id={`price-${p.id}`} name="price_cents" type="number" min={1} defaultValue={p.price_cents} />
              </div>
              {p.kind === "coin_pack" && (
                <div>
                  <label className="label" htmlFor={`coins-${p.id}`}>{t("nav.coins")}</label>
                  <input className="input" id={`coins-${p.id}`} name="coins" type="number" min={1} defaultValue={p.coins ?? 0} />
                </div>
              )}
              <div>
                <label className="label" htmlFor={`stripe-${p.id}`}>{t("admin.stripePriceId")}</label>
                <input className="input" id={`stripe-${p.id}`} name="stripe_price_id" defaultValue={p.stripe_price_id ?? ""} placeholder="price_…" />
              </div>
              <label className="flex items-center gap-2 self-end pb-3">
                <input type="checkbox" name="active" defaultChecked={p.active} /> {t("common.published")}
              </label>
            </ActionForm>
          </div>
        ))}
      </section>

      <section className="card space-y-3" aria-labelledby="pool">
        <h2 id="pool" className="h2">{t("admin.pool")}</h2>
        <p className="muted text-sm">{t("admin.poolText")}</p>
        <ActionForm action={distributePool} submitLabel={t("admin.distribute")} className="flex flex-wrap items-end gap-3">
          <div>
            <label className="label" htmlFor="month">{t("creator.month")}</label>
            <input className="input" id="month" name="month" type="month" required defaultValue={lastMonth.toISOString().slice(0, 7)} />
          </div>
        </ActionForm>
      </section>
    </div>
  );
}
