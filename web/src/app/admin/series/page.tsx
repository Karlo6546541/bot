import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { requireAdmin } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { setSeriesHidden } from "../actions";

export default async function AdminSeries() {
  await requireAdmin();
  const { t } = await getI18n();
  const { data: list } = await createAdminClient()
    .from("series")
    .select("id, slug, title, status, hidden_by_admin, moderation_note, creators(pen_name)")
    .order("updated_at", { ascending: false })
    .limit(300);
  return (
    <ul className="space-y-3">
      {(list ?? []).map((s) => (
        <li key={s.id} className="card flex flex-wrap items-center gap-3">
          <div className="min-w-0 flex-1">
            <Link href={`/series/${s.slug}`} className="font-semibold underline">{s.title}</Link>
            <p className="muted text-xs">
              {s.creators?.pen_name} · {t(s.status === "published" ? "common.published" : "common.draft")}
              {s.hidden_by_admin && ` · ${t("common.hidden")}: ${s.moderation_note ?? ""}`}
            </p>
          </div>
          <form action={setSeriesHidden.bind(null, s.id, !s.hidden_by_admin)} className="flex flex-wrap items-center gap-2">
            {!s.hidden_by_admin && (
              <>
                <label className="sr-only" htmlFor={`note-${s.id}`}>{t("admin.moderationNote")}</label>
                <input id={`note-${s.id}`} name="note" className="input min-h-10 w-48" placeholder={t("admin.moderationNote")} maxLength={500} />
              </>
            )}
            <button className={s.hidden_by_admin ? "btn-secondary" : "btn-danger"}>
              {t(s.hidden_by_admin ? "admin.unhide" : "admin.hide")}
            </button>
          </form>
        </li>
      ))}
    </ul>
  );
}
