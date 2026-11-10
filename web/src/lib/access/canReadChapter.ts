/**
 * The single source of truth for "can this user read this chapter?".
 * Pure + synchronous so it is trivially unit-testable. The SQL function
 * public.can_user_read_chapter mirrors this rule for RLS — keep them in sync.
 */

export type ChapterAccess = "free" | "locked" | "early_access";
export type Role = "reader" | "creator" | "admin";

export interface AccessSeries {
  creatorId: string;
  status: "draft" | "published";
  hiddenByAdmin: boolean;
  freeChapters: number;
}

export interface AccessChapter {
  id: string;
  number: number;
  access: ChapterAccess;
  coinPrice: number;
  published: boolean;
  publishAt: Date;
  earlyAccessUntil: Date | null;
}

export interface AccessUser {
  id: string;
  role: Role;
  hasActiveSubscription: boolean;
  unlockedChapterIds: ReadonlySet<string>;
}

export type AccessGrant = "owner" | "admin" | "free" | "subscription" | "unlocked";
export type AccessDenial = "not_available" | "login_required" | "locked";

export type AccessDecision =
  | { allowed: true; reason: AccessGrant }
  | { allowed: false; reason: AccessDenial; coinPrice: number; earlyAccessUntil: Date | null };

/** Is the chapter visible to the public at `now` (released, series public)? */
export function isChapterReleased(series: AccessSeries, chapter: AccessChapter, now: Date): boolean {
  return (
    series.status === "published" &&
    !series.hiddenByAdmin &&
    chapter.published &&
    chapter.publishAt.getTime() <= now.getTime()
  );
}

/** Free for everyone right now (no subscription / unlock needed)? */
export function isChapterFree(series: AccessSeries, chapter: AccessChapter, now: Date): boolean {
  switch (chapter.access) {
    case "free":
      return true;
    case "locked":
      return chapter.number <= series.freeChapters;
    case "early_access":
      // Early access overrides the "first N free" rule until the window ends.
      return chapter.earlyAccessUntil !== null && chapter.earlyAccessUntil.getTime() <= now.getTime();
  }
}

/** Is the chapter in its early-access window right now? */
export function isInEarlyAccess(chapter: AccessChapter, now: Date): boolean {
  return (
    chapter.access === "early_access" &&
    chapter.earlyAccessUntil !== null &&
    chapter.earlyAccessUntil.getTime() > now.getTime()
  );
}

export function canReadChapter(input: {
  user: AccessUser | null;
  series: AccessSeries;
  chapter: AccessChapter;
  now: Date;
}): AccessDecision {
  const { user, series, chapter, now } = input;
  const deny = (reason: AccessDenial): AccessDecision => ({
    allowed: false,
    reason,
    coinPrice: chapter.coinPrice,
    earlyAccessUntil: isInEarlyAccess(chapter, now) ? chapter.earlyAccessUntil : null,
  });

  if (user?.role === "admin") return { allowed: true, reason: "admin" };
  if (user && user.id === series.creatorId) return { allowed: true, reason: "owner" };

  if (!isChapterReleased(series, chapter, now)) return deny("not_available");
  if (isChapterFree(series, chapter, now)) return { allowed: true, reason: "free" };

  if (!user) return deny("login_required");
  if (user.hasActiveSubscription) return { allowed: true, reason: "subscription" };
  if (user.unlockedChapterIds.has(chapter.id)) return { allowed: true, reason: "unlocked" };
  return deny("locked");
}

/** Badge shown in chapter lists. */
export type ChapterBadge = "free" | "early_access" | "locked" | "unlocked" | "subscription";

export function chapterBadge(
  user: AccessUser | null,
  series: AccessSeries,
  chapter: AccessChapter,
  now: Date,
): ChapterBadge {
  if (isChapterFree(series, chapter, now)) return "free";
  if (user?.unlockedChapterIds.has(chapter.id)) return "unlocked";
  if (user?.hasActiveSubscription) return "subscription";
  return isInEarlyAccess(chapter, now) ? "early_access" : "locked";
}
