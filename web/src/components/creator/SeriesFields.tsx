import { getI18n } from "@/lib/i18n/server";
import { GENRES } from "@/config/monetization";
import type { Series } from "@/lib/supabase/types";

export async function SeriesFields({ series }: { series?: Series }) {
  const { t } = await getI18n();
  return (
    <>
      <div>
        <label className="label" htmlFor="title">{t("creator.title")}</label>
        <input className="input" id="title" name="title" required maxLength={120} defaultValue={series?.title} />
      </div>
      <div>
        <label className="label" htmlFor="slug">{t("creator.slug")}</label>
        <input className="input" id="slug" name="slug" maxLength={80} pattern="[a-z0-9\-]*" defaultValue={series?.slug} />
      </div>
      <div>
        <label className="label" htmlFor="description">{t("creator.description")}</label>
        <textarea className="input min-h-32" id="description" name="description" maxLength={4000} defaultValue={series?.description} />
      </div>
      <fieldset>
        <legend className="label">{t("creator.genres")}</legend>
        <div className="flex flex-wrap gap-2">
          {GENRES.map((g) => (
            <label key={g} className="flex min-h-10 items-center gap-2 rounded-lg border border-ink-200 px-3 dark:border-ink-700">
              <input type="checkbox" name="genres" value={g} defaultChecked={series?.genres.includes(g)} />
              {t(`genres.${g}`)}
            </label>
          ))}
        </div>
      </fieldset>
      <div>
        <label className="label" htmlFor="free_chapters">{t("creator.freeChapters")}</label>
        <input className="input w-32" id="free_chapters" name="free_chapters" type="number" min={0} max={1000} defaultValue={series?.free_chapters ?? 3} />
      </div>
    </>
  );
}
