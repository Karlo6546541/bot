/**
 * Integration tests against local Supabase (npm run db:start && npm run seed).
 * Verifies that locked content is unreachable from the client without
 * authorization, and that clients cannot write money tables.
 */
import { beforeAll, describe, expect, it } from "vitest";
import { canReadChapter } from "@/lib/access/canReadChapter";
import { toAccessChapter, toAccessSeries } from "@/lib/access/mappers";
import { anon, chapterBySeries, createTempUser, service, signedIn, type DB } from "./helpers";

const S1 = "sjene-nad-gornjim-gradom"; // free_chapters=3, ch6 early access

describe("RLS: chapter pages", () => {
  let reader: DB, subscriber: DB, otherCreator: DB;
  beforeAll(async () => {
    reader = await createTempUser("reader").then((u) => u.client);
    subscriber = await signedIn("pretplatnik@kadar.test");
    otherCreator = await signedIn("marko@kadar.test");
  });

  it("anonymous users can read pages of free chapters", async () => {
    const ch = await chapterBySeries(S1, 1);
    const { data } = await anon().from("chapter_pages").select("id").eq("chapter_id", ch.id);
    expect(data?.length).toBeGreaterThan(0);
  });

  it("anonymous users and plain readers cannot read pages of locked chapters", async () => {
    const ch = await chapterBySeries(S1, 4);
    for (const c of [anon(), reader, otherCreator]) {
      const { data } = await c.from("chapter_pages").select("id, storage_path").eq("chapter_id", ch.id);
      expect(data).toEqual([]);
    }
  });

  it("subscribers can read pages of locked and early-access chapters", async () => {
    for (const n of [4, 6]) {
      const ch = await chapterBySeries(S1, n);
      const { data } = await subscriber.from("chapter_pages").select("id").eq("chapter_id", ch.id);
      expect(data?.length).toBeGreaterThan(0);
    }
  });

  it("the private pages bucket cannot be downloaded or listed directly", async () => {
    const ch = await chapterBySeries(S1, 1); // even a FREE chapter goes through signed URLs
    const path = `${ch.series_id}/${ch.id}/page-1.jpg`;
    const dl = await anon().storage.from("pages").download(path);
    expect(dl.data).toBeNull();
    const dl2 = await reader.storage.from("pages").download(path);
    expect(dl2.data).toBeNull();
    const list = await reader.storage.from("pages").list(ch.series_id);
    expect(list.data ?? []).toEqual([]);
    const sign = await reader.storage.from("pages").createSignedUrl(path, 60);
    expect(sign.data).toBeNull();
  });

  it("scheduled chapters are invisible to the public", async () => {
    const ch = await chapterBySeries("orbita-velebit", 5);
    const { data } = await anon().from("chapters").select("id").eq("id", ch.id);
    expect(data).toEqual([]);
  });

  it("SQL rule matches the TypeScript rule for every seeded chapter and user", async () => {
    const db = service();
    const { data: chapters } = await db.from("chapters").select("*, series(*)");
    const users = await db.from("profiles").select("id, role");
    const subs = await db.from("subscriptions").select("user_id").eq("status", "active").gt("current_period_end", new Date().toISOString());
    const unlocks = await db.from("chapter_unlocks").select("user_id, chapter_id");
    const subSet = new Set(subs.data!.map((s) => s.user_id));
    for (const u of [...users.data!, null]) {
      for (const ch of chapters!) {
        const { data: sql } = await db.rpc("can_user_read_chapter", { p_chapter: ch.id, p_user: u?.id ?? (null as unknown as string) });
        const ts = canReadChapter({
          user: u
            ? {
                id: u.id,
                role: u.role,
                hasActiveSubscription: subSet.has(u.id),
                unlockedChapterIds: new Set(unlocks.data!.filter((x) => x.user_id === u.id).map((x) => x.chapter_id)),
              }
            : null,
          series: toAccessSeries(ch.series!),
          chapter: toAccessChapter(ch),
          now: new Date(),
        });
        expect(sql, `user=${u?.id ?? "anon"} chapter=${ch.series!.slug}#${ch.number}`).toBe(ts.allowed);
      }
    }
  });
});

describe("RLS: money tables are read-only for clients", () => {
  it("a reader cannot grant themselves coins, subscriptions or unlocks", async () => {
    const u = await createTempUser("hacker");
    const ch = await chapterBySeries(S1, 4);
    const r1 = await u.client.from("coin_balances").update({ balance: 9999 }).eq("user_id", u.id).select();
    expect(r1.error ?? r1.data?.length === 0).toBeTruthy();
    const r2 = await u.client.from("chapter_unlocks").insert({ user_id: u.id, chapter_id: ch.id, coins_spent: 0 });
    expect(r2.error).not.toBeNull();
    const r3 = await u.client.from("subscriptions").insert({
      user_id: u.id,
      provider: "mock",
      provider_subscription_id: "x" + u.id,
      status: "active",
      current_period_start: new Date().toISOString(),
      current_period_end: new Date(Date.now() + 1e9).toISOString(),
    });
    expect(r3.error).not.toBeNull();
    const r4 = await u.client.rpc("apply_coin_credit", { p_user: u.id, p_amount: 100, p_type: "admin_grant" });
    expect(r4.error).not.toBeNull();
    const r5 = await u.client.rpc("can_user_read_chapter", { p_chapter: ch.id, p_user: u.id });
    expect(r5.error).not.toBeNull();
    const { data: bal } = await service().from("coin_balances").select("balance").eq("user_id", u.id).single();
    expect(bal?.balance).toBe(0);
  });

  it("a reader cannot promote themselves to admin or approve themselves as creator", async () => {
    const u = await createTempUser("climber");
    const r1 = await u.client.from("profiles").update({ role: "admin" }).eq("id", u.id);
    expect(r1.error).not.toBeNull();
    const r2 = await u.client.from("creators").insert({ id: u.id, pen_name: "X Y", status: "approved" } as never);
    expect(r2.error).not.toBeNull();
    const r3 = await u.client.from("creators").insert({ id: u.id, pen_name: "X Y" });
    expect(r3.error).toBeNull();
    const { data } = await service().from("creators").select("status").eq("id", u.id).single();
    expect(data?.status).toBe("pending");
    // pending creators cannot create series
    const r4 = await u.client.from("series").insert({ creator_id: u.id, slug: `x-${Date.now()}`, title: "X" });
    expect(r4.error).not.toBeNull();
  });

  it("users only see their own transactions", async () => {
    const a = await createTempUser("a");
    await service().rpc("apply_coin_credit", { p_user: a.id, p_amount: 7, p_type: "admin_grant" });
    const b = await createTempUser("b");
    const { data } = await b.client.from("coin_transactions").select("id").eq("user_id", a.id);
    expect(data).toEqual([]);
  });
});

describe("apply_chapter_unlock", () => {
  it("unlocks atomically, is idempotent, and refuses when balance is too low", async () => {
    const db = service();
    const u = await createTempUser("unlocker");
    const ch = await chapterBySeries(S1, 5);
    const args = {
      p_user: u.id,
      p_chapter: ch.id,
      p_price: 5,
      p_creator: ch.series!.creator_id,
      p_series: ch.series_id,
      p_gross_cents: 50,
      p_creator_cents: 33,
      p_platform_cents: 17,
      p_share_pct: 65,
      p_period: "2026-11-01",
    };
    const poor = await db.rpc("apply_chapter_unlock", args);
    expect(poor.data).toMatchObject({ status: "insufficient_coins", balance: 0 });

    await db.rpc("apply_coin_credit", { p_user: u.id, p_amount: 8, p_type: "admin_grant" });
    const ok = await db.rpc("apply_chapter_unlock", args);
    expect(ok.data).toMatchObject({ status: "unlocked", balance: 3 });
    const again = await db.rpc("apply_chapter_unlock", args);
    expect(again.data).toMatchObject({ status: "already_unlocked", balance: 3 });

    const { data: pages } = await u.client.from("chapter_pages").select("id").eq("chapter_id", ch.id);
    expect(pages?.length).toBeGreaterThan(0);
    const { data: earnings } = await db.from("creator_earnings").select("*").eq("ref", `unlock:${u.id}:${ch.id}`);
    expect(earnings).toHaveLength(1);
  });
});

describe("creator & admin RPCs", () => {
  it("only the owner can replace a chapter's pages, and only with its own storage paths", async () => {
    const ch = await chapterBySeries(S1, 2); // Ana's series
    const other = await signedIn("marko@kadar.test");
    const r1 = await other.rpc("replace_chapter_pages", {
      p_chapter: ch.id,
      p_pages: [{ storage_path: `${ch.series_id}/${ch.id}/x.webp`, width: 1, height: 1 }],
    });
    expect(r1.error).not.toBeNull();
    const ana = await signedIn("ana@kadar.test");
    const r2 = await ana.rpc("replace_chapter_pages", {
      p_chapter: ch.id,
      p_pages: [{ storage_path: `someone-else/${ch.id}/x.webp`, width: 1, height: 1 }],
    });
    expect(r2.error).not.toBeNull();
    const { data } = await service().from("chapter_pages").select("id").eq("chapter_id", ch.id);
    expect(data?.length).toBe(4); // unchanged
  });

  it("earnings_summary returns only the caller's earnings", async () => {
    const marko = await signedIn("marko@kadar.test");
    const { data: markoId } = await service().rpc("admin_find_user_by_email", { p_email: "marko@kadar.test" });
    const { data } = await marko.rpc("earnings_summary", {});
    expect((data ?? []).every((r) => r.creator_id === markoId)).toBe(true);
    const reader = await createTempUser("nosy");
    const { data: none } = await reader.client.rpc("earnings_summary", {});
    expect(none).toEqual([]);
  });

  it("admin lookup functions are not callable by clients", async () => {
    const u = await createTempUser("snoop");
    expect((await u.client.rpc("admin_find_user_by_email", { p_email: "admin@kadar.test" })).error).not.toBeNull();
    expect((await u.client.rpc("sum_payments", { p_period: "2026-11-01", p_kind: "subscription" })).error).not.toBeNull();
  });
});
