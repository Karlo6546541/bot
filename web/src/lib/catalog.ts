import "server-only";
import { createClient } from "@/lib/supabase/server";
import { normalizeSearch } from "@/lib/format";
import { GENRES } from "@/config/monetization";
import type { Chapter, Series } from "@/lib/supabase/types";

export type SeriesCardData = Pick<Series, "id" | "slug" | "title" | "cover_path" | "genres" | "updated_at"> & {
  creators: { pen_name: string } | null;
};

const CARD_COLS = "id, slug, title, cover_path, genres, updated_at, creators(pen_name)";

/** Public catalog (RLS hides drafts / hidden series). */
export async function listSeries(opts: { q?: string; genre?: string; limit?: number } = {}): Promise<SeriesCardData[]> {
  const supabase = await createClient();
  let query = supabase
    .from("series")
    .select(CARD_COLS)
    .eq("status", "published")
    .eq("hidden_by_admin", false)
    .order("updated_at", { ascending: false })
    .limit(opts.limit ?? 60);
  const q = opts.q ? normalizeSearch(opts.q) : "";
  if (q) query = query.ilike("search_text", `%${q}%`);
  if (opts.genre && (GENRES as readonly string[]).includes(opts.genre)) query = query.contains("genres", [opts.genre]);
  const { data } = await query;
  return (data ?? []) as SeriesCardData[];
}

export async function getSeriesBySlug(slug: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("series")
    .select("*, creators(id, pen_name, bio)")
    .eq("slug", slug)
    .maybeSingle();
  return data as (Series & { creators: { id: string; pen_name: string; bio: string } | null }) | null;
}

/** Chapters visible to the current user (released ones; owners also see drafts). */
export async function listChapters(seriesId: string): Promise<Chapter[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("chapters").select("*").eq("series_id", seriesId).order("number");
  return data ?? [];
}

export async function getUserSeriesState(userId: string, seriesId: string) {
  const supabase = await createClient();
  const [follow, progress] = await Promise.all([
    supabase.from("follows").select("series_id").eq("user_id", userId).eq("series_id", seriesId).maybeSingle(),
    supabase
      .from("reading_progress")
      .select("chapter_id, completed, updated_at, page_index")
      .eq("user_id", userId)
      .eq("series_id", seriesId)
      .order("updated_at", { ascending: false }),
  ]);
  return { following: !!follow.data, progress: progress.data ?? [] };
}

export type ProgressEntry = {
  chapter_id: string;
  series_id: string;
  page_index: number;
  completed: boolean;
  updated_at: string;
  chapters: { number: number; title: string } | null;
  series: { slug: string; title: string; cover_path: string | null } | null;
};

export async function getReadingHistory(userId: string, limit = 30): Promise<ProgressEntry[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("reading_progress")
    .select("chapter_id, series_id, page_index, completed, updated_at, chapters(number, title), series(slug, title, cover_path)")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false })
    .limit(limit);
  return ((data ?? []) as ProgressEntry[]).filter((p) => p.series && p.chapters);
}

/** Most recent chapter per series. */
export function continueReading(history: ProgressEntry[], max = 6): ProgressEntry[] {
  const seen = new Set<string>();
  const out: ProgressEntry[] = [];
  for (const h of history) {
    if (seen.has(h.series_id)) continue;
    seen.add(h.series_id);
    out.push(h);
    if (out.length >= max) break;
  }
  return out;
}

export async function getFollowedSeries(userId: string): Promise<SeriesCardData[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("follows")
    .select(`created_at, series(${CARD_COLS})`)
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  return (data ?? []).map((f) => f.series as unknown as SeriesCardData).filter(Boolean);
}
