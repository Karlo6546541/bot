import Link from "next/link";
import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { requireCreator } from "@/lib/auth/creator";
import { createClient } from "@/lib/supabase/server";
import { coverUrl } from "@/lib/supabase/storage";
import { formatDateTime } from "@/lib/format";
import { ActionForm } from "@/components/creator/ActionForm";
import { SeriesFields } from "@/components/creator/SeriesFields";
import { CoverUploader } from "@/components/creator/CoverUploader";
import { ConfirmButton } from "@/components/forms/ConfirmButton";
import { deleteSeries, setSeriesStatus, updateSeries } from "../../actions";

export default async function EditSeriesPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const viewer = await requireCreator(`/creator/series/${id}`);
  const { t, locale } = await getI18n();
  const supabase = await createClient();
  const { data: series } = await supabase.from("series").select("*").eq("id", id).eq("creator_id", viewer.id).maybeSingle();
  if (!series) notFound();
  const { data: chapters } = await supabase
    .from("chapters")
    .select("id, number, title, access, published, publish_at, chapter_pages(count)")
    .eq("series_id", id)
    .order("number");
  const now = Date.now();
  const published = series.status === "published";

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="h1">{series.title}</h1>
        <div className="flex flex-wrap gap-2">
          {published && <Link href={`/series/${series.slug}`} className="btn-ghost">{t("creator.viewPublic")}</Link>}
          <form action={setSeriesStatus.bind(null, id, published ? "draft" : "published")}>
            <button className={published ? "btn-secondary" : "btn-primary"}>
              {t(published ? "creator.unpublishSeries" : "creator.publishSeries")}
            </button>
          </form>
        </div>
      </div>
      {series.hidden_by_admin && (
        <p role="alert" className="rounded-lg bg-red-100 p-3 text-sm text-red-900">
          {t("creator.hiddenByAdmin", { note: series.moderation_note ?? "" })}
        </p>
      )}

      <section className="card space-y-4">
        <CoverUploader seriesId={id} currentUrl={coverUrl(series.cover_path)} />
        <ActionForm action={updateSeries.bind(null, id)} submitLabel={t("common.save")}>
          <SeriesFields series={series} />
        </ActionForm>
      </section>

      <section aria-labelledby="ch" className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 id="ch" className="h2">{t("creator.chapters")}</h2>
          <Link href={`/creator/chapters/new?series=${id}`} className="btn-primary">+ {t("creator.newChapter")}</Link>
        </div>
        <ol className="divide-y divide-ink-100 rounded-xl border border-ink-100 bg-white dark:divide-ink-800 dark:border-ink-800 dark:bg-ink-900">
          {(chapters ?? []).map((c) => {
            const state = !c.published ? "draft" : new Date(c.publish_at).getTime() > now ? "scheduled" : "published";
            const pages = (c.chapter_pages as unknown as { count: number }[])[0]?.count ?? 0;
            return (
              <li key={c.id}>
                <Link href={`/creator/chapters/${c.id}`} className="flex min-h-14 items-center gap-3 px-4 py-2 hover:bg-ink-50 dark:hover:bg-ink-800">
                  <span className="w-10 font-bold text-ink-500">#{c.number}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate">{c.title || t("series.chapterN", { n: c.number })}</span>
                    <span className="muted text-xs">
                      {t("common.pageCount", { count: pages })} · {formatDateTime(c.publish_at, locale)}
                    </span>
                  </span>
                  <span className={c.access === "free" ? "badge-free" : c.access === "early_access" ? "badge-early" : "badge-locked"}>
                    {t(c.access === "free" ? "common.free" : c.access === "early_access" ? "common.earlyAccess" : "common.locked")}
                  </span>
                  <span className={state === "published" ? "badge-free" : state === "scheduled" ? "badge-early" : "badge-locked"}>
                    {t(`common.${state}`)}
                  </span>
                </Link>
              </li>
            );
          })}
        </ol>
      </section>

      {!published && (
        <form action={deleteSeries.bind(null, id)}>
          <ConfirmButton className="btn-danger" message={t("creator.deleteSeriesConfirm")}>{t("common.delete")}</ConfirmButton>
        </form>
      )}
    </div>
  );
}
