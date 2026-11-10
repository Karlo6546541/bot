import type { Metadata } from "next";
import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { requireCreator } from "@/lib/auth/creator";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("creator.dashboard") };
}

export default async function CreatorDashboard() {
  const viewer = await requireCreator();
  const { t } = await getI18n();
  const supabase = await createClient();
  const { data: series } = await supabase
    .from("series")
    .select("id, slug, title, status, hidden_by_admin, chapters(count)")
    .eq("creator_id", viewer.id)
    .order("updated_at", { ascending: false });
  // Aggregate counts only (ownership already established by the query above).
  const ids = (series ?? []).map((s) => s.id);
  const admin = createAdminClient();
  const [follows, reads] = ids.length
    ? await Promise.all([
        admin.from("follows").select("series_id").in("series_id", ids),
        admin.from("chapter_reads").select("series_id").in("series_id", ids),
      ])
    : [{ data: [] }, { data: [] }];
  const count = (rows: { series_id: string }[] | null, id: string) => (rows ?? []).filter((r) => r.series_id === id).length;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="h1">{t("creator.dashboard")}</h1>
        <div className="flex gap-2">
          <Link href="/creator/earnings" className="btn-secondary">{t("creator.earnings")}</Link>
          <Link href="/creator/series/new" className="btn-primary">+ {t("creator.newSeries")}</Link>
        </div>
      </div>
      <h2 className="h2">{t("creator.mySeries")}</h2>
      {!series?.length ? (
        <p className="muted">{t("creator.noSeries")}</p>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {series.map((s) => (
            <li key={s.id}>
              <Link href={`/creator/series/${s.id}`} className="card block hover:border-brand-500">
                <p className="font-semibold">{s.title}</p>
                <p className="mt-1 flex flex-wrap gap-2 text-xs">
                  <span className={s.status === "published" ? "badge-free" : "badge-locked"}>
                    {t(s.status === "published" ? "common.published" : "common.draft")}
                  </span>
                  {s.hidden_by_admin && <span className="badge bg-red-100 text-red-900">{t("common.hidden")}</span>}
                </p>
                <dl className="muted mt-2 grid grid-cols-3 text-xs">
                  <div><dt>{t("creator.chapters")}</dt><dd className="font-bold">{(s.chapters as unknown as { count: number }[])[0]?.count ?? 0}</dd></div>
                  <div><dt>{t("creator.followers")}</dt><dd className="font-bold">{count(follows.data, s.id)}</dd></div>
                  <div><dt>{t("creator.views")}</dt><dd className="font-bold">{count(reads.data, s.id)}</dd></div>
                </dl>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
