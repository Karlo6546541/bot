import type { Metadata } from "next";
import { getI18n } from "@/lib/i18n/server";
import { listSeries } from "@/lib/catalog";
import { GENRES } from "@/config/monetization";
import { SeriesCard, SeriesGrid } from "@/components/series/SeriesCard";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("browse.title") };
}

export default async function BrowsePage({ searchParams }: { searchParams: Promise<{ q?: string; genre?: string }> }) {
  const { t } = await getI18n();
  const { q = "", genre = "" } = await searchParams;
  const results = await listSeries({ q, genre });
  return (
    <div className="space-y-6">
      <h1 className="h1">{t("browse.title")}</h1>
      {/* Plain GET form: works without JavaScript and is shareable via URL. */}
      <form role="search" className="grid gap-3 sm:grid-cols-[1fr_220px_auto]" action="/browse">
        <div>
          <label htmlFor="q" className="label">{t("browse.searchLabel")}</label>
          <input id="q" name="q" type="search" defaultValue={q} className="input" placeholder={t("browse.searchPlaceholder")} />
        </div>
        <div>
          <label htmlFor="genre" className="label">{t("browse.genre")}</label>
          <select id="genre" name="genre" defaultValue={genre} className="input">
            <option value="">{t("browse.allGenres")}</option>
            {GENRES.map((g) => (
              <option key={g} value={g}>{t(`genres.${g}`)}</option>
            ))}
          </select>
        </div>
        <button className="btn-primary self-end">{t("common.search")}</button>
      </form>
      <p className="muted text-sm" aria-live="polite">{t("browse.results", { count: results.length })}</p>
      {results.length === 0 ? (
        <p>{t("browse.noResults")}</p>
      ) : (
        <SeriesGrid>
          {results.map((s) => (
            <SeriesCard key={s.id} series={s} />
          ))}
        </SeriesGrid>
      )}
    </div>
  );
}
