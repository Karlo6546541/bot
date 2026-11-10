"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth/session";

export async function toggleFollow(seriesId: string, slug: string, follow: boolean) {
  const viewer = await getViewer();
  if (!viewer) redirect(`/login?next=/series/${slug}`);
  const supabase = await createClient();
  if (follow) {
    await supabase.from("follows").upsert({ user_id: viewer.id, series_id: seriesId }, { ignoreDuplicates: true });
  } else {
    await supabase.from("follows").delete().eq("user_id", viewer.id).eq("series_id", seriesId);
  }
  revalidatePath(`/series/${slug}`);
  revalidatePath("/library");
}
