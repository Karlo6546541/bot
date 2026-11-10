import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { getSeriesBySlug, getUserSeriesState, listChapters } from "@/lib/catalog";
import { getViewer } from "@/lib/auth/session";
import { loadAccessUser, toAccessChapter, toAccessSeries } from "@/lib/access/server";
import { chapterBadge, isChapterReleased } from "@/lib/access/canReadChapter";
import { coverUrl } from "@/lib/supabase/storage";
import { formatDate } from "@/lib/format";
import { toggleFollow } from "../actions";
import type { MessageKey } from "@/lib/i18n";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const s = await getSeriesBySlug((await params).slug);
  if (!s) return {};
  return { title: s.title, description: s.description.slice(0, 160) };
}

const badgeClass = {
  free: "badge-free",
  early_access: "badge-early",
  locked: "badge-locked",
  unlocked: "badge-unlocked",
  subscription: "badge-unlocked",
} as const;

export default async function SeriesPage({ params }: Props) {
  const { slug } = await params;
  const { t, locale } = await getI18n();
  const series = await getSeriesBySlug(slug);
  if (!series) notFound();
  const viewer = await getViewer();
  const now = new Date();
  const allChapters = await listChapters(series.id);
  const aSeries = toAccessSeries(series);
  const chapters = allChapters.filter((c) => isChapterReleased(aSeries, toAccessChapter(c), now));
  const [accessUser, state] = viewer
    ? await Promise.all([
        loadAccessUser(viewer.id, viewer.profile.role, chapters.map((c) => c.id)),
        getUserSeriesState(viewer.id, series.id),
      ])
    : [null, null];
  const readIds = new Set(state?.progress.filter((p) => p.completed).map((p) => p.chapter_id));
  const lastRead = state?.progress[0];
  const lastChapter = lastRead ? chapters.find((c) => c.id === lastRead.chapter_id) : undefined;
  const cover = coverUrl(series.cover_path);
  const isOwner = viewer?.id === series.creator_id;

  return (
    <article className="space-y-8">
      <header className="grid gap-5 sm:grid-cols-[220px_1fr]">
        <div className="relative mx-auto aspect-[2/3] w-44 overflow-hidden rounded-xl bg-ink-200 sm:w-full dark:bg-ink-800">
          {cover && <Image src={cover} alt="" fill priority sizes="220px" className="object-cover" />}
        </div>
        <div className="space-y-3">
          <h1 className="h1">{series.title}</h1>
          <p className="muted">{t("common.by", { name: series.creators?.pen_name ?? "" })}</p>
          <ul className="flex flex-wrap gap-2" aria-label={t("browse.genre")}>
            {series.genres.map((g) => (
              <li key={g}>
                <Link href={`/browse?genre=${g}`} className="badge-locked">{t(`genres.${g}` as MessageKey)}</Link>
              </li>
            ))}
          </ul>
          <p className="whitespace-pre-line leading-relaxed">{series.description}</p>
          {series.free_chapters > 0 && (
            <p className="text-sm font-medium text-emerald-700 dark:text-emerald-400">
              {t("series.freeChaptersInfo", { count: series.free_chapters })}
            </p>
          )}
          <div className="flex flex-wrap gap-2 pt-1">
            {lastChapter ? (
              <Link href={`/read/${lastChapter.id}`} className="btn-primary">
                {t("series.continue", { n: lastChapter.number })}
              </Link>
            ) : chapters[0] ? (
              <Link href={`/read/${chapters[0].id}`} className="btn-primary">{t("series.startReading")}</Link>
            ) : null}
            {viewer ? (
              <form action={toggleFollow.bind(null, series.id, series.slug, !state?.following)}>
                <button className="btn-secondary" aria-pressed={state?.following}>
                  {state?.following ? `✓ ${t("series.following")}` : `+ ${t("series.follow")}`}
                </button>
              </form>
            ) : (
              <Link href={`/login?next=/series/${series.slug}`} className="btn-secondary">+ {t("series.follow")}</Link>
            )}
            {isOwner && <Link href={`/creator/series/${series.id}`} className="btn-ghost">{t("common.edit")}</Link>}
          </div>
        </div>
      </header>

      <section aria-labelledby="chapters">
        <h2 id="chapters" className="h2 mb-3">
          {t("series.chapters")} <span className="muted text-base font-normal">({chapters.length})</span>
        </h2>
        {chapters.length === 0 ? (
          <p className="muted">{t("series.noChapters")}</p>
        ) : (
          <ol className="divide-y divide-ink-100 overflow-hidden rounded-xl border border-ink-100 bg-white dark:divide-ink-800 dark:border-ink-800 dark:bg-ink-900">
            {[...chapters].reverse().map((c) => {
              const ac = toAccessChapter(c);
              const badge = chapterBadge(accessUser, aSeries, ac, now);
              const label =
                badge === "free" ? t("common.free")
                : badge === "early_access" ? t("common.earlyAccess")
                : badge === "locked" ? `🔒 ${t("common.coinCount", { count: c.coin_price })}`
                : t("common.unlocked");
              return (
                <li key={c.id}>
                  <Link href={`/read/${c.id}`} className="flex min-h-14 items-center gap-3 px-4 py-3 hover:bg-ink-50 dark:hover:bg-ink-800">
                    <span className="w-10 shrink-0 text-sm font-bold text-ink-500">#{c.number}</span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">
                        {c.title || t("series.chapterN", { n: c.number })}
                        {readIds.has(c.id) && <span className="sr-only">, {t("series.readStatus")}</span>}
                      </span>
                      <span className="muted block text-xs">
                        {formatDate(c.publish_at, locale)}
                        {badge === "early_access" && c.early_access_until &&
                          ` · ${t("series.earlyUntil", { date: formatDate(c.early_access_until, locale) })}`}
                      </span>
                    </span>
                    {readIds.has(c.id) && <span aria-hidden className="text-emerald-600">✓</span>}
                    <span className={badgeClass[badge]}>{label}</span>
                  </Link>
                </li>
              );
            })}
          </ol>
        )}
      </section>
    </article>
  );
}
