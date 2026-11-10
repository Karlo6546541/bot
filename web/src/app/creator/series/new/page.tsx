import { getI18n } from "@/lib/i18n/server";
import { requireCreator } from "@/lib/auth/creator";
import { ActionForm } from "@/components/creator/ActionForm";
import { SeriesFields } from "@/components/creator/SeriesFields";
import { createSeries } from "../../actions";

export default async function NewSeriesPage() {
  await requireCreator("/creator/series/new");
  const { t } = await getI18n();
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <h1 className="h1">{t("creator.newSeries")}</h1>
      <ActionForm action={createSeries} submitLabel={t("common.save")}>
        <SeriesFields />
      </ActionForm>
    </div>
  );
}
