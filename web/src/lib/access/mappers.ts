import type { Chapter, Series } from "@/lib/supabase/types";
import type { AccessChapter, AccessSeries } from "./canReadChapter";

export function toAccessSeries(
  s: Pick<Series, "creator_id" | "status" | "hidden_by_admin" | "free_chapters">,
): AccessSeries {
  return {
    creatorId: s.creator_id,
    status: s.status,
    hiddenByAdmin: s.hidden_by_admin,
    freeChapters: s.free_chapters,
  };
}

export function toAccessChapter(
  c: Pick<Chapter, "id" | "number" | "access" | "coin_price" | "published" | "publish_at" | "early_access_until">,
): AccessChapter {
  return {
    id: c.id,
    number: c.number,
    access: c.access,
    coinPrice: c.coin_price,
    published: c.published,
    publishAt: new Date(c.publish_at),
    earlyAccessUntil: c.early_access_until ? new Date(c.early_access_until) : null,
  };
}
