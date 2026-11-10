import Link from "next/link";
import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { requireCreator } from "@/lib/auth/creator";
import { createClient } from "@/lib/supabase/server";
import { signChapterPages } from "@/lib/access/server";
import { ChapterForm } from "@/components/creator/ChapterForm";
import { PageManager } from "@/components/creator/PageManager";
import { ConfirmButton } from "@/components/forms/ConfirmButton";
import { deleteChapter, updateChapter } from "../../actions";

const DAY = 86_400_000;

export default async function EditChapterPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const viewer = await requireCreator(`/creator/chapters/${id}`);
  const { t } = await getI18n();
  const supabase = await createClient();
  const { data: chapter } = await supabase.from("chapters").select("*, series!inner(id, title, creator_id)").eq("id", id).maybeSingle();
  if (!chapter || chapter.series.creator_id !== viewer.id) notFound();
  // Owner: ownership verified above, so signing is allowed.
  const [{ pages }, { data: rows }] = await Promise.all([
    signChapterPages(id),
    supabase.from("chapter_pages").select("id, storage_path").eq("chapter_id", id).order("position"),
  ]);
  const pathById = new Map((rows ?? []).map((r) => [r.id, r.storage_path]));
  const earlyDays =
    chapter.early_access_until
      ? Math.max(1, Math.round((new Date(chapter.early_access_until).getTime() - new Date(chapter.publish_at).getTime()) / DAY))
      : 7;

  return (
    <div className="space-y-8">
      <div>
        <Link href={`/creator/series/${chapter.series.id}`} className="muted text-sm underline">← {chapter.series.title}</Link>
        <h1 className="h1 mt-1">{t("series.chapterN", { n: chapter.number })}</h1>
      </div>
      <section className="card">
        <ChapterForm
          action={updateChapter.bind(null, id)}
          defaults={{
            number: chapter.number,
            title: chapter.title,
            access: chapter.access,
            coinPrice: chapter.coin_price,
            earlyDays,
            publishAt: chapter.publish_at,
            published: chapter.published,
          }}
        />
      </section>
      <PageManager
        seriesId={chapter.series.id}
        chapterId={id}
        initialPages={pages.map((p) => ({
          key: p.id,
          storagePath: pathById.get(p.id) ?? "",
          width: p.width,
          height: p.height,
          previewUrl: p.url,
        }))}
      />
      <form action={deleteChapter.bind(null, id, chapter.series.id)}>
        <ConfirmButton className="btn-danger" message={t("creator.deleteChapterConfirm")}>{t("common.delete")}</ConfirmButton>
      </form>
    </div>
  );
}
