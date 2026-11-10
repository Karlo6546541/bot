import { describe, expect, it } from "vitest";
import {
  canReadChapter,
  chapterBadge,
  type AccessChapter,
  type AccessSeries,
  type AccessUser,
} from "@/lib/access/canReadChapter";

const NOW = new Date("2026-11-10T12:00:00Z");
const DAY = 86_400_000;

const series = (o: Partial<AccessSeries> = {}): AccessSeries => ({
  creatorId: "creator-1",
  status: "published",
  hiddenByAdmin: false,
  freeChapters: 3,
  ...o,
});
const chapter = (o: Partial<AccessChapter> = {}): AccessChapter => ({
  id: "ch-5",
  number: 5,
  access: "locked",
  coinPrice: 5,
  published: true,
  publishAt: new Date(NOW.getTime() - DAY),
  earlyAccessUntil: null,
  ...o,
});
const user = (o: Partial<AccessUser> = {}): AccessUser => ({
  id: "user-1",
  role: "reader",
  hasActiveSubscription: false,
  unlockedChapterIds: new Set(),
  ...o,
});

describe("canReadChapter", () => {
  it("first N chapters are free for everyone, including anonymous users", () => {
    for (const n of [1, 2, 3]) {
      expect(canReadChapter({ user: null, series: series(), chapter: chapter({ number: n }), now: NOW })).toEqual({
        allowed: true,
        reason: "free",
      });
    }
  });

  it("chapter N+1 is locked; anonymous users are asked to log in", () => {
    const d = canReadChapter({ user: null, series: series(), chapter: chapter({ number: 4 }), now: NOW });
    expect(d).toMatchObject({ allowed: false, reason: "login_required", coinPrice: 5 });
  });

  it("free_chapters = 0 locks everything not explicitly free", () => {
    const d = canReadChapter({ user: user(), series: series({ freeChapters: 0 }), chapter: chapter({ number: 1 }), now: NOW });
    expect(d).toMatchObject({ allowed: false, reason: "locked" });
  });

  it("access=free is free regardless of number", () => {
    const d = canReadChapter({ user: null, series: series(), chapter: chapter({ number: 99, access: "free" }), now: NOW });
    expect(d).toEqual({ allowed: true, reason: "free" });
  });

  it("logged-in reader without sub/unlock is locked", () => {
    expect(canReadChapter({ user: user(), series: series(), chapter: chapter(), now: NOW })).toMatchObject({
      allowed: false,
      reason: "locked",
    });
  });

  it("active subscription grants access to locked chapters", () => {
    expect(
      canReadChapter({ user: user({ hasActiveSubscription: true }), series: series(), chapter: chapter(), now: NOW }),
    ).toEqual({ allowed: true, reason: "subscription" });
  });

  it("coin unlock grants permanent access to that chapter only", () => {
    const u = user({ unlockedChapterIds: new Set(["ch-5"]) });
    expect(canReadChapter({ user: u, series: series(), chapter: chapter(), now: NOW })).toEqual({
      allowed: true,
      reason: "unlocked",
    });
    expect(
      canReadChapter({ user: u, series: series(), chapter: chapter({ id: "ch-6", number: 6 }), now: NOW }),
    ).toMatchObject({ allowed: false, reason: "locked" });
  });

  describe("early access", () => {
    const early = chapter({ access: "early_access", earlyAccessUntil: new Date(NOW.getTime() + 3 * DAY) });

    it("is locked during the window and reports when it becomes free", () => {
      const d = canReadChapter({ user: user(), series: series(), chapter: early, now: NOW });
      expect(d).toMatchObject({ allowed: false, reason: "locked", earlyAccessUntil: early.earlyAccessUntil });
    });

    it("overrides the first-N-free rule during the window", () => {
      const d = canReadChapter({ user: user(), series: series(), chapter: { ...early, number: 1 }, now: NOW });
      expect(d.allowed).toBe(false);
    });

    it("is readable with subscription or coins during the window", () => {
      expect(canReadChapter({ user: user({ hasActiveSubscription: true }), series: series(), chapter: early, now: NOW }).allowed).toBe(true);
      expect(
        canReadChapter({ user: user({ unlockedChapterIds: new Set([early.id]) }), series: series(), chapter: early, now: NOW }).allowed,
      ).toBe(true);
    });

    it("becomes free for everyone once the window has passed (boundary inclusive)", () => {
      const at = early.earlyAccessUntil!;
      expect(canReadChapter({ user: null, series: series(), chapter: early, now: at })).toEqual({ allowed: true, reason: "free" });
      expect(canReadChapter({ user: null, series: series(), chapter: early, now: new Date(at.getTime() - 1) }).allowed).toBe(false);
    });
  });

  describe("availability", () => {
    it("scheduled (future) chapters are not available even to subscribers", () => {
      const d = canReadChapter({
        user: user({ hasActiveSubscription: true }),
        series: series(),
        chapter: chapter({ number: 1, publishAt: new Date(NOW.getTime() + DAY) }),
        now: NOW,
      });
      expect(d).toMatchObject({ allowed: false, reason: "not_available" });
    });

    it("draft chapters, draft series and admin-hidden series are not available", () => {
      const cases = [
        { series: series(), chapter: chapter({ number: 1, published: false }) },
        { series: series({ status: "draft" }), chapter: chapter({ number: 1 }) },
        { series: series({ hiddenByAdmin: true }), chapter: chapter({ number: 1 }) },
      ];
      for (const c of cases) {
        expect(canReadChapter({ user: user({ hasActiveSubscription: true }), now: NOW, ...c })).toMatchObject({
          allowed: false,
          reason: "not_available",
        });
      }
    });

    it("an unlocked chapter that was later hidden is not available", () => {
      const d = canReadChapter({
        user: user({ unlockedChapterIds: new Set(["ch-5"]) }),
        series: series({ hiddenByAdmin: true }),
        chapter: chapter(),
        now: NOW,
      });
      expect(d.allowed).toBe(false);
    });
  });

  it("the series owner can always read their own chapters (incl. drafts)", () => {
    const d = canReadChapter({
      user: user({ id: "creator-1", role: "creator" }),
      series: series({ status: "draft" }),
      chapter: chapter({ published: false }),
      now: NOW,
    });
    expect(d).toEqual({ allowed: true, reason: "owner" });
  });

  it("another creator gets no special treatment", () => {
    const d = canReadChapter({ user: user({ id: "creator-2", role: "creator" }), series: series(), chapter: chapter(), now: NOW });
    expect(d.allowed).toBe(false);
  });

  it("admins can read everything", () => {
    const d = canReadChapter({
      user: user({ role: "admin" }),
      series: series({ hiddenByAdmin: true }),
      chapter: chapter({ published: false }),
      now: NOW,
    });
    expect(d).toEqual({ allowed: true, reason: "admin" });
  });
});

describe("chapterBadge", () => {
  it("labels chapters for list views", () => {
    const early = chapter({ access: "early_access", earlyAccessUntil: new Date(NOW.getTime() + DAY) });
    expect(chapterBadge(null, series(), chapter({ number: 1 }), NOW)).toBe("free");
    expect(chapterBadge(null, series(), chapter(), NOW)).toBe("locked");
    expect(chapterBadge(null, series(), early, NOW)).toBe("early_access");
    expect(chapterBadge(user({ unlockedChapterIds: new Set(["ch-5"]) }), series(), chapter(), NOW)).toBe("unlocked");
    expect(chapterBadge(user({ hasActiveSubscription: true }), series(), chapter(), NOW)).toBe("subscription");
  });
});
