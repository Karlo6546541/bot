import { NextResponse } from "next/server";
import { z } from "zod";
import { getViewer } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

const body = z.object({
  chapterId: z.string().uuid(),
  pageIndex: z.number().int().min(0).max(10000),
  scrollRatio: z.number().min(0).max(1),
  completed: z.boolean(),
});

export async function POST(req: Request) {
  const viewer = await getViewer();
  if (!viewer) return NextResponse.json({ error: "unauthenticated" }, { status: 401 });
  const parsed = body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "invalid" }, { status: 400 });
  const supabase = await createClient();
  // RLS: the chapter must be visible to this user; series id comes from the DB, not the client.
  const { data: chapter } = await supabase.from("chapters").select("series_id").eq("id", parsed.data.chapterId).maybeSingle();
  if (!chapter) return NextResponse.json({ error: "not_found" }, { status: 404 });
  const { data: existing } = await supabase
    .from("reading_progress")
    .select("completed")
    .eq("user_id", viewer.id)
    .eq("chapter_id", parsed.data.chapterId)
    .maybeSingle();
  const { error } = await supabase.from("reading_progress").upsert({
    user_id: viewer.id,
    chapter_id: parsed.data.chapterId,
    series_id: chapter.series_id,
    page_index: parsed.data.pageIndex,
    scroll_ratio: parsed.data.scrollRatio,
    completed: parsed.data.completed || !!existing?.completed, // once read, stays read
    updated_at: new Date().toISOString(),
  });
  if (error) return NextResponse.json({ error: "failed" }, { status: 500 });
  return new NextResponse(null, { status: 204 });
}
