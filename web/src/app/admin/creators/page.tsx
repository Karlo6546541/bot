import { getI18n } from "@/lib/i18n/server";
import { requireAdmin } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { formatDate } from "@/lib/format";
import { reviewCreator } from "../actions";

export default async function AdminCreators() {
  await requireAdmin();
  const { t, locale } = await getI18n();
  const db = createAdminClient();
  const { data: list } = await db.from("creators").select("*").order("created_at", { ascending: false }).limit(200);
  const { data: emails } = await db.rpc("admin_user_emails", { p_ids: (list ?? []).map((c) => c.id) });
  const emailOf = new Map((emails ?? []).map((e) => [e.id, e.email]));
  const pending = (list ?? []).filter((c) => c.status === "pending");
  const others = (list ?? []).filter((c) => c.status !== "pending");
  return (
    <div className="space-y-8">
      <section aria-labelledby="pending" className="space-y-3">
        <h2 id="pending" className="h2">{t("admin.applications")}</h2>
        {!pending.length && <p className="muted">{t("admin.noApplications")}</p>}
        {pending.map((c) => (
          <article key={c.id} className="card space-y-2">
            <h3 className="font-semibold">{c.pen_name} <span className="muted text-sm font-normal">{emailOf.get(c.id)}</span></h3>
            <p className="muted text-xs">{formatDate(c.created_at, locale)}</p>
            {c.bio && <p className="text-sm">{c.bio}</p>}
            {c.application_note && <p className="text-sm italic">“{c.application_note}”</p>}
            {c.portfolio_url && (
              <a className="text-sm text-brand-600 underline" href={c.portfolio_url} target="_blank" rel="noopener noreferrer nofollow">{c.portfolio_url}</a>
            )}
            <div className="flex gap-2 pt-1">
              <form action={reviewCreator.bind(null, c.id, "approved")}><button className="btn-primary">{t("admin.approve")}</button></form>
              <form action={reviewCreator.bind(null, c.id, "rejected")}><button className="btn-secondary">{t("admin.reject")}</button></form>
            </div>
          </article>
        ))}
      </section>
      <section aria-labelledby="all" className="overflow-x-auto">
        <h2 id="all" className="h2 mb-2">{t("admin.creators")}</h2>
        <table className="table">
          <tbody>
            {others.map((c) => (
              <tr key={c.id}>
                <td>{c.pen_name}<span className="muted block text-xs">{emailOf.get(c.id)}</span></td>
                <td><span className={c.status === "approved" ? "badge-free" : "badge-locked"}>{c.status}</span></td>
                <td className="text-right">
                  <form action={reviewCreator.bind(null, c.id, c.status === "approved" ? "rejected" : "approved")}>
                    <button className="btn-ghost">{t(c.status === "approved" ? "admin.reject" : "admin.approve")}</button>
                  </form>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
