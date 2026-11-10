import { notFound } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { requireCreator } from "@/lib/auth/creator";
import { createClient } from "@/lib/supabase/server";
import { ChapterForm } from "@/components/creator/ChapterForm";
import { monetizationDefaults } from "@/config/monetization";
import { createChapter } from "../../actions";

export default async function NewChapterPage({ searchParams }: { searchParams: Promise<{ series?: string }> }) {
  const { series: seriesId = "" } = await searchParams;
  const viewer = await requireCreator(`/creator/chapters/new?series=${seriesId}`);
  const { t } = await getI18n();
  const supabase = await createClient();
  const { data: series } = await supabase.from("series").select("id, title").eq("id", seriesId).eq("creator_id", viewer.id).maybeSingle();
  if (!series) notFound();
  const { data: last } = await supabase.from("chapters").select("number").eq("series_id", series.id).order("number", { ascending: false }).limit(1).maybeSingle();
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <p className="muted">{series.title}</p>
      <h1 className="h1">{t("creator.newChapter")}</h1>
      <ChapterForm
        action={createChapter.bind(null, series.id)}
        defaults={{
          number: (last?.number ?? 0) + 1,
          title: "",
          access: "locked",
          coinPrice: monetizationDefaults.defaultCoinPrice,
          earlyDays: 7,
          publishAt: null,
          published: false,
        }}
      />
    </div>
  );
}
