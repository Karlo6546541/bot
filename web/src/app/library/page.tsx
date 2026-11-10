import type { Metadata } from "next";
import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { requireViewer } from "@/lib/auth/session";
import { continueReading, getFollowedSeries, getReadingHistory } from "@/lib/catalog";
import { SeriesCard, SeriesGrid } from "@/components/series/SeriesCard";
import { formatDateTime } from "@/lib/format";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("library.title") };
}

export default async function LibraryPage() {
  const viewer = await requireViewer("/library");
  const { t, locale } = await getI18n();
  const [followed, history] = await Promise.all([getFollowedSeries(viewer.id), getReadingHistory(viewer.id, 50)]);
  const cont = continueReading(history, 8);
  return (
    <div className="space-y-10">
      <h1 className="h1">{t("library.title")}</h1>

      <section aria-labelledby="cont">
        <h2 id="cont" className="h2 mb-3">{t("library.continueReading")}</h2>
        {cont.length === 0 ? (
          <p className="muted">{t("library.emptyHistory")}</p>
        ) : (
          <ul className="grid gap-2 sm:grid-cols-2">
            {cont.map((p) => (
              <li key={p.chapter_id}>
                <Link href={`/read/${p.chapter_id}`} className="card flex items-center justify-between gap-3 hover:border-brand-500">
                  <span className="min-w-0">
                    <span className="block truncate font-semibold">{p.series!.title}</span>
                    <span className="muted block text-xs">{t("library.lastRead", { n: p.chapters!.number })}</span>
                  </span>
                  <span aria-hidden className="text-brand-600">▶</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section aria-labelledby="following">
        <h2 id="following" className="h2 mb-3">{t("library.following")}</h2>
        {followed.length === 0 ? (
          <p className="muted">
            {t("library.emptyFollowing")} <Link className="underline" href="/browse">{t("nav.browse")}</Link>
          </p>
        ) : (
          <SeriesGrid>{followed.map((s) => <SeriesCard key={s.id} series={s} />)}</SeriesGrid>
        )}
      </section>

      <section aria-labelledby="history">
        <h2 id="history" className="h2 mb-3">{t("library.history")}</h2>
        {history.length === 0 ? (
          <p className="muted">{t("library.emptyHistory")}</p>
        ) : (
          <ol className="divide-y divide-ink-100 rounded-xl border border-ink-100 bg-white dark:divide-ink-800 dark:border-ink-800 dark:bg-ink-900">
            {history.map((h) => (
              <li key={h.chapter_id}>
                <Link href={`/read/${h.chapter_id}`} className="flex min-h-12 items-center gap-3 px-4 py-2 hover:bg-ink-50 dark:hover:bg-ink-800">
                  <span className="min-w-0 flex-1 truncate">
                    {h.series!.title} — {t("series.chapterN", { n: h.chapters!.number })}
                  </span>
                  {h.completed && <span className="text-emerald-600" aria-label={t("series.readStatus")}>✓</span>}
                  <time className="muted text-xs" dateTime={h.updated_at}>{formatDateTime(h.updated_at, locale)}</time>
                </Link>
              </li>
            ))}
          </ol>
        )}
      </section>
    </div>
  );
}
