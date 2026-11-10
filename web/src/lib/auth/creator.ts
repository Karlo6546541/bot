import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireViewer, type Viewer } from "./session";

/** Approved creator (or admin acting as one); otherwise go to the application page. */
export async function requireCreator(next = "/creator"): Promise<Viewer> {
  const viewer = await requireViewer(next);
  const supabase = await createClient();
  const { data } = await supabase.from("creators").select("status").eq("id", viewer.id).maybeSingle();
  if (data?.status !== "approved") redirect("/creator/apply");
  return viewer;
}
