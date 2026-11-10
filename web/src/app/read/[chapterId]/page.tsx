import type { Metadata } from "next";
import Link from "next/link";
import { after } from "next/server";
import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { getViewer } from "@/lib/auth/session";
import { checkChapterAccess, recordChapterRead, signChapterPages } from "@/lib/access/server";
import { createClient } from "@/lib/supabase/server";
import { Reader } from "@/components/reader/Reader";
import { LockedChapter } from "@/components/reader/LockedChapter";

type Props = { params: Promise<{ chapterId: string }> };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { chapterId } = await params;
  if (!UUID.test(chapterId)) return {};
  const supabase = await createClient();
  const { data } = await supabase.from("chapters").select("number, title, series(title)").eq("id", chapterId).maybeSingle();
  if (!data) return {};
  const { t } = await getI18n();
  return { title: `${data.series?.title} — ${t("series.chapterN", { n: data.number })}`, robots: { index: false } };
}

export default async function ReadPage({ params }: Props) {
  const { chapterId } = await params;
  if (!UUID.test(chapterId)) notFound();
  const { t } = await getI18n();
  const viewer = await getViewer();
  const ctx = await checkChapterAccess(chapterId, viewer ? { id: viewer.id, role: viewer.profile.role } : null);
  if (!ctx) notFound();
  const { chapter, series, decision } = ctx;

  // Neighbours among chapters this user can see (RLS).
  const supabase = await createClient();
  const { data: siblings } = await supabase
    .from("chapters")
    .select("id, number, published, publish_at")
    .eq("series_id", series.id)
    .order("number");
  const now = Date.now();
  const visible = (siblings ?? []).filter((c) => c.published && new Date(c.publish_at).getTime() <= now);
  const idx = visible.findIndex((c) => c.id === chapter.id);
  const prev = idx > 0 ? visible[idx - 1] : null;
  const next = idx >= 0 && idx < visible.length - 1 ? visible[idx + 1] : null;

  if (!decision.allowed) {
    if (decision.reason === "not_available") notFound();
    let balance = 0;
    if (viewer) {
      const { data } = await supabase.from("coin_balances").select("balance").eq("user_id", viewer.id).maybeSingle();
      balance = data?.balance ?? 0;
    }
    return (
      <LockedChapter
        chapterId={chapter.id}
        seriesSlug={series.slug}
        seriesTitle={series.title}
        chapterNumber={chapter.number}
        chapterTitle={chapter.title}
        decision={decision}
        balance={balance}
        loggedIn={!!viewer}
      />
    );
  }

  const [{ pages, expiresAt }, progress] = await Promise.all([
    signChapterPages(chapter.id),
    viewer
      ? supabase
          .from("reading_progress")
          .select("page_index, scroll_ratio")
          .eq("user_id", viewer.id)
          .eq("chapter_id", chapter.id)
          .maybeSingle()
          .then((r) => r.data)
      : Promise.resolve(null),
  ]);

  if (viewer && decision.reason !== "owner" && decision.reason !== "admin") {
    after(() => recordChapterRead(viewer.id, chapter, series, decision.reason));
  }

  return (
    <Reader
      key={chapter.id}
      chapterId={chapter.id}
      seriesSlug={series.slug}
      seriesTitle={series.title}
      chapterNumber={chapter.number}
      chapterTitle={chapter.title}
      initialPages={pages}
      initialExpiresAt={expiresAt}
      initialProgress={progress ? { pageIndex: progress.page_index, scrollRatio: progress.scroll_ratio } : null}
      prevChapterId={prev?.id ?? null}
      nextChapterId={next?.id ?? null}
      loggedIn={!!viewer}
      emptyText={t("reader.noPages")}
    />
  );
}
