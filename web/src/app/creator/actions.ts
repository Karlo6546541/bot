"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth/session";
import { GENRES } from "@/config/monetization";
import { slugify } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";

export type ActionState = { error?: MessageKey; ok?: MessageKey } | undefined;
const DAY = 86_400_000;

async function authed() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login?next=/creator");
  return { viewer, supabase: await createClient() };
}

// ---------------------------------------------------------------- application
const applySchema = z.object({
  pen_name: z.string().trim().min(2).max(60),
  bio: z.string().trim().max(2000),
  portfolio_url: z.union([z.literal(""), z.string().url().max(300)]),
  application_note: z.string().trim().max(2000),
});

export async function applyAsCreator(_p: ActionState, fd: FormData): Promise<ActionState> {
  const { viewer, supabase } = await authed();
  const parsed = applySchema.safeParse(Object.fromEntries(fd));
  if (!parsed.success) return { error: "errors.invalidInput" };
  const { error } = await supabase.from("creators").insert({
    id: viewer.id,
    ...parsed.data,
    portfolio_url: parsed.data.portfolio_url || null,
  });
  if (error) return { error: "common.error" };
  revalidatePath("/creator/apply");
  return { ok: "creator.pendingTitle" };
}

// ---------------------------------------------------------------- series
const seriesSchema = z.object({
  title: z.string().trim().min(1).max(120),
  slug: z.string().trim().max(80).optional(),
  description: z.string().trim().max(4000),
  free_chapters: z.coerce.number().int().min(0).max(1000),
  genres: z.array(z.enum(GENRES)).max(4),
});

function parseSeries(fd: FormData) {
  return seriesSchema.safeParse({
    title: fd.get("title"),
    slug: fd.get("slug") || undefined,
    description: fd.get("description") ?? "",
    free_chapters: fd.get("free_chapters") ?? 3,
    genres: fd.getAll("genres"),
  });
}

export async function createSeries(_p: ActionState, fd: FormData): Promise<ActionState> {
  const { viewer, supabase } = await authed();
  const parsed = parseSeries(fd);
  if (!parsed.success) return { error: "errors.invalidInput" };
  const slug = slugify(parsed.data.slug || parsed.data.title);
  if (!slug) return { error: "errors.invalidInput" };
  const { data, error } = await supabase
    .from("series")
    .insert({ ...parsed.data, slug, creator_id: viewer.id, status: "draft" })
    .select("id")
    .single();
  if (error) return { error: error.code === "23505" ? "creator.slugTaken" : "common.error" };
  redirect(`/creator/series/${data.id}`);
}

export async function updateSeries(seriesId: string, _p: ActionState, fd: FormData): Promise<ActionState> {
  const { supabase } = await authed();
  const parsed = parseSeries(fd);
  if (!parsed.success) return { error: "errors.invalidInput" };
  const slug = slugify(parsed.data.slug || parsed.data.title);
  const { data, error } = await supabase
    .from("series")
    .update({ ...parsed.data, slug })
    .eq("id", seriesId)
    .select("slug");
  if (error) return { error: error.code === "23505" ? "creator.slugTaken" : "common.error" };
  if (!data?.length) return { error: "errors.forbidden" };
  revalidatePath(`/creator/series/${seriesId}`);
  revalidatePath(`/series/${slug}`);
  return { ok: "common.saved" };
}

export async function setSeriesStatus(seriesId: string, status: "draft" | "published") {
  const { supabase } = await authed();
  await supabase.from("series").update({ status }).eq("id", seriesId);
  revalidatePath(`/creator/series/${seriesId}`);
  revalidatePath("/", "layout");
}

export async function setSeriesCover(seriesId: string, path: string) {
  const { supabase } = await authed();
  if (!path.startsWith(`${seriesId}/`)) throw new Error("invalid path");
  const { data: old } = await supabase.from("series").select("cover_path").eq("id", seriesId).single();
  const { error } = await supabase.from("series").update({ cover_path: path }).eq("id", seriesId);
  if (error) throw new Error(error.message);
  if (old?.cover_path && old.cover_path !== path) await supabase.storage.from("covers").remove([old.cover_path]);
  revalidatePath(`/creator/series/${seriesId}`);
}

export async function deleteSeries(seriesId: string) {
  const { supabase } = await authed();
  await supabase.from("series").delete().eq("id", seriesId).eq("status", "draft");
  redirect("/creator");
}

// ---------------------------------------------------------------- chapters
const chapterSchema = z
  .object({
    number: z.coerce.number().int().min(1).max(100000),
    title: z.string().trim().max(120),
    access: z.enum(["free", "locked", "early_access"]),
    coin_price: z.coerce.number().int().min(0).max(10000),
    early_days: z.coerce.number().int().min(1).max(365).optional(),
    publish_at: z.string().datetime({ offset: true }).optional().or(z.literal("")),
    published: z.boolean(),
  })
  .refine((v) => v.access !== "early_access" || v.early_days, { path: ["early_days"] });

function parseChapter(fd: FormData) {
  const parsed = chapterSchema.safeParse({
    number: fd.get("number"),
    title: fd.get("title") ?? "",
    access: fd.get("access"),
    coin_price: fd.get("coin_price"),
    early_days: fd.get("access") === "early_access" ? fd.get("early_days") : undefined,
    publish_at: fd.get("publish_at") || undefined,
    published: fd.get("published") === "on",
  });
  if (!parsed.success) return null;
  const { early_days, publish_at, ...rest } = parsed.data;
  const publishAt = publish_at ? new Date(publish_at) : new Date();
  return {
    ...rest,
    publish_at: publishAt.toISOString(),
    early_access_until:
      rest.access === "early_access" && early_days ? new Date(publishAt.getTime() + early_days * DAY).toISOString() : null,
  };
}

export async function createChapter(seriesId: string, _p: ActionState, fd: FormData): Promise<ActionState> {
  const { supabase } = await authed();
  const values = parseChapter(fd);
  if (!values) return { error: "errors.invalidInput" };
  const { data, error } = await supabase.from("chapters").insert({ ...values, series_id: seriesId }).select("id").single();
  if (error) return { error: error.code === "23505" ? "creator.chapterNumberTaken" : "common.error" };
  redirect(`/creator/chapters/${data.id}`);
}

export async function updateChapter(chapterId: string, _p: ActionState, fd: FormData): Promise<ActionState> {
  const { supabase } = await authed();
  const values = parseChapter(fd);
  if (!values) return { error: "errors.invalidInput" };
  const { data, error } = await supabase.from("chapters").update(values).eq("id", chapterId).select("series_id");
  if (error) return { error: error.code === "23505" ? "creator.chapterNumberTaken" : "common.error" };
  if (!data?.length) return { error: "errors.forbidden" };
  revalidatePath(`/creator/chapters/${chapterId}`);
  revalidatePath(`/creator/series/${data[0].series_id}`);
  return { ok: "common.saved" };
}

export async function deleteChapter(chapterId: string, seriesId: string) {
  const { supabase } = await authed();
  const { data: pages } = await supabase.from("chapter_pages").select("storage_path").eq("chapter_id", chapterId);
  const { error } = await supabase.from("chapters").delete().eq("id", chapterId);
  if (!error && pages?.length) await supabase.storage.from("pages").remove(pages.map((p) => p.storage_path));
  redirect(`/creator/series/${seriesId}`);
}

const pagesSchema = z
  .array(
    z.object({
      storage_path: z.string().min(1).max(300),
      width: z.number().int().positive().max(20000),
      height: z.number().int().positive().max(100000),
    }),
  )
  .max(500);

/** Saves order of pages; deletes storage objects that were removed. */
export async function saveChapterPages(chapterId: string, pages: unknown): Promise<{ ok: boolean }> {
  const { supabase } = await authed();
  const parsed = pagesSchema.safeParse(pages);
  if (!parsed.success) return { ok: false };
  const { data: before } = await supabase.from("chapter_pages").select("storage_path").eq("chapter_id", chapterId);
  const { error } = await supabase.rpc("replace_chapter_pages", { p_chapter: chapterId, p_pages: parsed.data });
  if (error) return { ok: false };
  const keep = new Set(parsed.data.map((p) => p.storage_path));
  const removed = (before ?? []).map((p) => p.storage_path).filter((p) => !keep.has(p));
  if (removed.length) await supabase.storage.from("pages").remove(removed);
  revalidatePath(`/creator/chapters/${chapterId}`);
  return { ok: true };
}
