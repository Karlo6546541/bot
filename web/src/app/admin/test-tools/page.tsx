import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { requireAdmin } from "@/lib/auth/session";
import { isMockPayments } from "@/lib/payments";
import { ActionForm } from "@/components/creator/ActionForm";
import { grantCoinsAction, grantSubscriptionAction } from "../actions";

export default async function TestTools() {
  await requireAdmin();
  if (!isMockPayments()) notFound();
  const { t } = await getI18n();
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      <section className="card space-y-3 border-amber-500" aria-labelledby="gc">
        <h2 id="gc" className="h2">{t("admin.grantCoins")}</h2>
        <ActionForm action={grantCoinsAction} submitLabel={t("admin.grantCoins")}>
          <div>
            <label className="label" htmlFor="gc-email">{t("admin.userEmail")}</label>
            <input className="input" id="gc-email" name="email" type="email" required />
          </div>
          <div>
            <label className="label" htmlFor="gc-amount">{t("admin.amount")}</label>
            <input className="input" id="gc-amount" name="amount" type="number" defaultValue={50} required />
          </div>
        </ActionForm>
      </section>
      <section className="card space-y-3 border-amber-500" aria-labelledby="gs">
        <h2 id="gs" className="h2">{t("admin.grantSubscription")}</h2>
        <ActionForm action={grantSubscriptionAction} submitLabel={t("admin.grantSubscription")}>
          <div>
            <label className="label" htmlFor="gs-email">{t("admin.userEmail")}</label>
            <input className="input" id="gs-email" name="email" type="email" required />
          </div>
          <div>
            <label className="label" htmlFor="gs-days">{t("admin.days")}</label>
            <input className="input" id="gs-days" name="days" type="number" min={1} defaultValue={30} required />
          </div>
        </ActionForm>
      </section>
    </div>
  );
}
