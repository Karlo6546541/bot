import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Chapter, Series } from "@/lib/supabase/types";
import { monetizationDefaults } from "@/config/monetization";
import { periodOf } from "@/lib/format";
import { canReadChapter, type AccessDecision, type AccessUser, type Role } from "./canReadChapter";
import { toAccessChapter, toAccessSeries } from "./mappers";

export { toAccessChapter, toAccessSeries };

/** Loads subscription + unlock state for a user (service role, explicit user id). */
export async function loadAccessUser(
  userId: string,
  role: Role,
  chapterIds?: string[],
): Promise<AccessUser> {
  const db = createAdminClient();
  const nowIso = new Date().toISOString();
  const subQ = db
    .from("subscriptions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", "active")
    .gt("current_period_end", nowIso);
  let unlockQ = db.from("chapter_unlocks").select("chapter_id").eq("user_id", userId);
  if (chapterIds) unlockQ = unlockQ.in("chapter_id", chapterIds.length ? chapterIds : ["00000000-0000-0000-0000-000000000000"]);
  const [sub, unlocks] = await Promise.all([subQ, unlockQ]);
  return {
    id: userId,
    role,
    hasActiveSubscription: (sub.count ?? 0) > 0,
    unlockedChapterIds: new Set((unlocks.data ?? []).map((u) => u.chapter_id)),
  };
}

export interface ChapterContext {
  chapter: Chapter;
  series: Series;
  decision: AccessDecision;
  accessUser: AccessUser | null;
}

/** Server-side access check for one chapter. Returns null if the chapter doesn't exist. */
export async function checkChapterAccess(
  chapterId: string,
  viewer: { id: string; role: Role } | null,
): Promise<ChapterContext | null> {
  const db = createAdminClient();
  const { data } = await db.from("chapters").select("*, series(*)").eq("id", chapterId).maybeSingle();
  if (!data || !data.series) return null;
  const { series, ...chapter } = data as Chapter & { series: Series };
  const accessUser = viewer ? await loadAccessUser(viewer.id, viewer.role, [chapterId]) : null;
  const decision = canReadChapter({
    user: accessUser,
    series: toAccessSeries(series),
    chapter: toAccessChapter(chapter),
    now: new Date(),
  });
  return { chapter, series, decision, accessUser };
}

export interface SignedPage {
  id: string;
  url: string;
  width: number;
  height: number;
}

/**
 * Returns short-lived signed URLs for a chapter's pages.
 * MUST only be called after `checkChapterAccess(...).decision.allowed`.
 */
export async function signChapterPages(chapterId: string): Promise<{ pages: SignedPage[]; expiresAt: number }> {
  const db = createAdminClient();
  const ttl = Number(process.env.SIGNED_URL_TTL_SECONDS) || monetizationDefaults.signedUrlTtlSeconds;
  const { data: rows } = await db
    .from("chapter_pages")
    .select("id, storage_path, width, height")
    .eq("chapter_id", chapterId)
    .order("position");
  const list = rows ?? [];
  if (list.length === 0) return { pages: [], expiresAt: Date.now() + ttl * 1000 };
  const { data: signed, error } = await db.storage.from("pages").createSignedUrls(
    list.map((r) => r.storage_path),
    ttl,
  );
  if (error || !signed) throw new Error(`Failed to sign page URLs: ${error?.message}`);
  const byPath = new Map(signed.map((s) => [s.path, s.signedUrl]));
  return {
    pages: list.map((r) => ({ id: r.id, url: byPath.get(r.storage_path) ?? "", width: r.width, height: r.height })),
    expiresAt: Date.now() + ttl * 1000,
  };
}

/** Records a read (used for stats and to split the subscription pool). */
export async function recordChapterRead(userId: string, chapter: Chapter, series: Series, reason: string) {
  const db = createAdminClient();
  await db.from("chapter_reads").upsert(
    {
      user_id: userId,
      chapter_id: chapter.id,
      series_id: series.id,
      creator_id: series.creator_id,
      access_reason: reason,
      period: periodOf(new Date()),
    },
    { onConflict: "user_id,chapter_id,period", ignoreDuplicates: true },
  );
}
