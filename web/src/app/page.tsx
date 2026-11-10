import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { continueReading, getReadingHistory, listSeries } from "@/lib/catalog";
import { getViewer } from "@/lib/auth/session";
import { SeriesCard, SeriesGrid } from "@/components/series/SeriesCard";

export default async function Home() {
  const { t } = await getI18n();
  const viewer = await getViewer();
  const [series, history] = await Promise.all([
    listSeries({ limit: 20 }),
    viewer ? getReadingHistory(viewer.id, 20) : Promise.resolve([]),
  ]);
  const cont = continueReading(history, 4);
  return (
    <div className="space-y-10">
      <section className="rounded-2xl bg-gradient-to-br from-ink-900 to-brand-700 px-5 py-8 text-white sm:px-8 sm:py-12">
        <h1 className="max-w-xl text-2xl font-black leading-tight sm:text-4xl">{t("home.heroTitle")}</h1>
        <p className="mt-3 max-w-xl text-sm text-white/85 sm:text-base">{t("home.heroText")}</p>
        <Link href="/browse" className="btn mt-5 bg-white text-ink-900 hover:bg-ink-100">
          {t("home.heroCta")}
        </Link>
      </section>

      {cont.length > 0 && (
        <section aria-labelledby="continue">
          <h2 id="continue" className="h2 mb-3">{t("home.continueReading")}</h2>
          <ul className="grid gap-2 sm:grid-cols-2">
            {cont.map((p) => (
              <li key={p.chapter_id}>
                <Link href={`/read/${p.chapter_id}`} className="card flex items-center justify-between gap-3 hover:border-brand-500">
                  <span className="font-semibold">{p.series!.title}</span>
                  <span className="muted text-sm">{t("series.chapterN", { n: p.chapters!.number })}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="latest">
        <h2 id="latest" className="h2 mb-3">{t("home.latest")}</h2>
        {series.length === 0 ? (
          <p className="muted">{t("home.empty")}</p>
        ) : (
          <SeriesGrid>
            {series.map((s, i) => (
              <SeriesCard key={s.id} series={s} priority={i < 4} />
            ))}
          </SeriesGrid>
        )}
      </section>
    </div>
  );
}
