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
import { CheckIcon, LockIcon, PlayIcon, PlusIcon } from "@/components/ui/Icons";

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
      <header className="relative grid gap-6 overflow-hidden rounded-2xl border-2 bg-[var(--surface)] p-5 sm:grid-cols-[220px_1fr] sm:p-7" style={{ borderColor: "var(--edge)", boxShadow: "6px 6px 0 0 var(--edge)" }}>
        {cover && (
          <Image src={cover} alt="" fill aria-hidden sizes="100vw" className="-z-0 scale-125 object-cover opacity-15 blur-2xl" />
        )}
        <div className="cover relative mx-auto w-44 sm:w-full">
          {cover && <Image src={cover} alt="" fill priority sizes="220px" className="object-cover" />}
        </div>
        <div className="relative space-y-3">
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
                <PlayIcon className="h-4 w-4" /> {t("series.continue", { n: lastChapter.number })}
              </Link>
            ) : chapters[0] ? (
              <Link href={`/read/${chapters[0].id}`} className="btn-primary"><PlayIcon className="h-4 w-4" /> {t("series.startReading")}</Link>
            ) : null}
            {viewer ? (
              <form action={toggleFollow.bind(null, series.id, series.slug, !state?.following)}>
                <button className="btn-secondary" aria-pressed={state?.following}>
                  {state?.following ? <><CheckIcon className="h-4 w-4" /> {t("series.following")}</> : <><PlusIcon className="h-4 w-4" /> {t("series.follow")}</>}
                </button>
              </form>
            ) : (
              <Link href={`/login?next=/series/${series.slug}`} className="btn-secondary"><PlusIcon className="h-4 w-4" /> {t("series.follow")}</Link>
            )}
            {isOwner && <Link href={`/creator/series/${series.id}`} className="btn-ghost">{t("common.edit")}</Link>}
          </div>
        </div>
      </header>

      <section aria-labelledby="chapters">
        <h2 id="chapters" className="caption mb-4">
          {t("series.chapters")} <span className="opacity-70">({chapters.length})</span>
        </h2>
        {chapters.length === 0 ? (
          <p className="muted">{t("series.noChapters")}</p>
        ) : (
          <ol className="divide-y-2 overflow-hidden rounded-xl border-2 bg-[var(--surface)]" style={{ borderColor: "var(--edge)", boxShadow: "4px 4px 0 0 var(--edge)" }}>
            {[...chapters].reverse().map((c) => {
              const ac = toAccessChapter(c);
              const badge = chapterBadge(accessUser, aSeries, ac, now);
              const label =
                badge === "free" ? t("common.free")
                : badge === "early_access" ? t("common.earlyAccess")
                : badge === "locked" ? t("common.coinCount", { count: c.coin_price })
                : t("common.unlocked");
              return (
                <li key={c.id}>
                  <Link href={`/read/${c.id}`} className="flex min-h-16 items-center gap-3 px-4 py-3 transition-colors hover:bg-sun/40">
                    <span className="w-10 shrink-0 text-2xl font-black text-brand-600" style={{ fontFamily: "var(--font-display)" }}>{c.number}</span>
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
                    {readIds.has(c.id) && <CheckIcon className="h-5 w-5 text-mint" />}
                    <span className={`${badgeClass[badge]} gap-1`}>{badge === "locked" && <LockIcon className="h-3 w-3" />}{label}</span>
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
