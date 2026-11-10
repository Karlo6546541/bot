/**
 * Demo data: users (all with password "lozinka123"), 3 series with chapters
 * and page images. Safe to re-run (skips existing series).
 *   npm run seed            (reads .env.local)
 */
import { createClient } from "@supabase/supabase-js";
import { readFileSync } from "node:fs";
import path from "node:path";
import type { Database } from "../src/lib/supabase/database.types";
import { PAGES_PER_CHAPTER, SEED_PASSWORD, seedSeries, seedUsers } from "./seed-data";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error("Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (see .env.example)");
const db = createClient<Database>(url, key, { auth: { persistSession: false } });
const assets = path.resolve(__dirname, "../supabase/seed-assets");
const DAY = 86_400_000;

function must<T>(res: { data: T; error: { message: string } | null }, what: string): NonNullable<T> {
  if (res.error || res.data == null) throw new Error(`${what}: ${res.error?.message ?? "no data"}`);
  return res.data as NonNullable<T>;
}

function ok(res: { error: { message: string } | null }, what: string) {
  if (res.error) throw new Error(`${what}: ${res.error.message}`);
}

async function ensureUser(email: string, displayName: string): Promise<string> {
  const created = await db.auth.admin.createUser({
    email,
    password: SEED_PASSWORD,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });
  if (created.data.user) return created.data.user.id;
  const { data: list } = await db.auth.admin.listUsers({ perPage: 1000 });
  const u = list.users.find((x) => x.email === email);
  if (!u) throw new Error(`Could not create ${email}: ${created.error?.message}`);
  return u.id;
}

async function main() {
  const ids: Record<string, string> = {};
  for (const u of seedUsers) {
    const id = await ensureUser(u.email, u.displayName);
    ids[u.email] = id;
    ok(await db.from("profiles").update({ role: u.role, display_name: u.displayName }).eq("id", id), "profile");
    if (u.role === "creator") {
      ok(
        await db.from("creators").upsert({
          id,
          pen_name: u.penName!,
          status: "approved",
          bio: "Izmišljeni autor za demo podatke.",
          reviewed_at: new Date().toISOString(),
        }),
        "creator",
      );
    }
    console.log(`user ${u.email} (${u.role})`);
  }

  // Test fixtures: one reader with coins, one with an active (mock) subscription.
  const reader = ids["citatelj@kadar.test"];
  await db.rpc("apply_coin_credit", { p_user: reader, p_amount: 20, p_type: "admin_grant", p_ref: "seed:coins", p_note: "seed" });
  const subscriber = ids["pretplatnik@kadar.test"];
  const { data: plan } = await db.from("pricing_plans").select("id").eq("code", "monthly").single();
  ok(
    await db.from("subscriptions").upsert(
      {
        user_id: subscriber,
        plan_id: plan?.id ?? null,
        provider: "mock",
        provider_subscription_id: `mock_sub_seed_${subscriber}`,
        status: "active",
        current_period_start: new Date().toISOString(),
        current_period_end: new Date(Date.now() + 30 * DAY).toISOString(),
      },
      { onConflict: "provider_subscription_id" },
    ),
    "subscription",
  );

  for (const s of seedSeries) {
    const existing = await db.from("series").select("id").eq("slug", s.slug).maybeSingle();
    if (existing.data) {
      console.log(`series ${s.slug} exists — skipped`);
      continue;
    }
    const series = must(
      await db
        .from("series")
        .insert({
          creator_id: ids[s.creatorEmail],
          slug: s.slug,
          title: s.title,
          description: s.description,
          genres: s.genres,
          free_chapters: s.freeChapters,
          status: "published",
        })
        .select()
        .single(),
      "series",
    );
    const coverPath = `${series.id}/cover.jpg`;
    ok(
      await db.storage
        .from("covers")
        .upload(coverPath, readFileSync(path.join(assets, s.slug, "cover.jpg")), { contentType: "image/jpeg", upsert: true }),
      "cover upload",
    );
    await db.from("series").update({ cover_path: coverPath }).eq("id", series.id);

    const now = Date.now();
    for (const [i, ch] of s.chapters.entries()) {
      const number = i + 1;
      // Older chapters were released earlier (one week apart).
      const publishAt = new Date(
        ch.publishInDays ? now + ch.publishInDays * DAY : now - (s.chapters.length - number) * 7 * DAY - DAY,
      );
      const chapter = must(
        await db
          .from("chapters")
          .insert({
            series_id: series.id,
            number,
            title: ch.title,
            access: ch.access ?? "locked",
            coin_price: 5,
            published: true,
            publish_at: publishAt.toISOString(),
            early_access_until: ch.earlyDays ? new Date(now + ch.earlyDays * DAY).toISOString() : null,
          })
          .select()
          .single(),
        "chapter",
      );
      const pages = [];
      for (let p = 1; p <= PAGES_PER_CHAPTER; p++) {
        const storagePath = `${series.id}/${chapter.id}/page-${p}.jpg`;
        ok(
          await db.storage
            .from("pages")
            .upload(storagePath, readFileSync(path.join(assets, s.slug, `page-${p}.jpg`)), {
              contentType: "image/jpeg",
              upsert: true,
            }),
          "page upload",
        );
        pages.push({ chapter_id: chapter.id, position: p - 1, storage_path: storagePath, width: 800, height: 1200 });
      }
      ok(await db.from("chapter_pages").insert(pages), "pages");
    }
    console.log(`series ${s.slug}: ${s.chapters.length} chapters`);
  }
  console.log(`\nDone. All demo accounts use password "${SEED_PASSWORD}".`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
