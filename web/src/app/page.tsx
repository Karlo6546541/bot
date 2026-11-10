import Image from "next/image";
import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { continueReading, getReadingHistory, listSeries } from "@/lib/catalog";
import { getViewer } from "@/lib/auth/session";
import { coverUrl } from "@/lib/supabase/storage";
import { SeriesCard, SeriesGrid } from "@/components/series/SeriesCard";
import { ArrowRightIcon, PlayIcon } from "@/components/ui/Icons";

export default async function Home() {
  const { t } = await getI18n();
  const viewer = await getViewer();
  const [series, history] = await Promise.all([
    listSeries({ limit: 20 }),
    viewer ? getReadingHistory(viewer.id, 20) : Promise.resolve([]),
  ]);
  const cont = continueReading(history, 4);
  const featured = series[0];
  const featuredCover = coverUrl(featured?.cover_path);

  return (
    <div className="space-y-12">
      <section
        className="relative overflow-hidden rounded-2xl border-2 bg-ink-900 text-white"
        style={{ borderColor: "var(--edge)", boxShadow: "6px 6px 0 0 var(--edge)" }}
      >
        <div aria-hidden className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,#ff5a36_0,transparent_55%),radial-gradient(circle_at_90%_90%,#4f8cff_0,transparent_50%)] opacity-90" />
        <div aria-hidden className="absolute inset-0 opacity-25 [background-image:radial-gradient(#000_1.2px,transparent_1.6px)] [background-size:10px_10px]" />
        <div className="relative grid items-center gap-6 p-6 sm:grid-cols-[1.3fr_1fr] sm:p-10">
          <div>
            <span className="caption">{t("common.tagline")}</span>
            <h1
              className="mt-4 text-[clamp(2rem,7vw,3.6rem)] font-black uppercase leading-[0.95] tracking-tight [text-shadow:3px_3px_0_#14120e]"
              style={{ fontFamily: "var(--font-display)" }}
            >
              {t("home.heroTitle")}
            </h1>
            <p className="mt-4 max-w-md text-sm font-medium text-white/90 sm:text-base">{t("home.heroText")}</p>
            <div className="mt-6 flex flex-wrap gap-3">
              <Link href="/browse" className="btn-primary">{t("home.heroCta")} <ArrowRightIcon className="h-4 w-4" /></Link>
              <Link href="/pricing" className="btn-secondary">{t("nav.pricing")}</Link>
            </div>
          </div>
          {featured && featuredCover && (
            <Link href={`/series/${featured.slug}`} className="group mx-auto block w-40 rotate-3 sm:w-52" aria-label={featured.title}>
              <div className="cover !shadow-[6px_6px_0_0_#14120e]">
                <Image src={featuredCover} alt="" fill priority sizes="208px" className="object-cover" />
              </div>
            </Link>
          )}
        </div>
      </section>

      {cont.length > 0 && (
        <section aria-labelledby="continue" className="space-y-4">
          <h2 id="continue" className="caption">{t("home.continueReading")}</h2>
          <ul className="grid gap-3 sm:grid-cols-2">
            {cont.map((p) => (
              <li key={p.chapter_id}>
                <Link href={`/read/${p.chapter_id}`} className="card flex items-center justify-between gap-3">
                  <span className="min-w-0">
                    <span className="block truncate font-black uppercase tracking-tight">{p.series!.title}</span>
                    <span className="muted text-xs font-bold">{t("series.chapterN", { n: p.chapters!.number })}</span>
                  </span>
                  <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full border-2 bg-brand-500 text-white" style={{ borderColor: "var(--edge)" }}>
                    <PlayIcon className="h-4 w-4" />
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="latest" className="space-y-5">
        <h2 id="latest" className="caption">{t("home.latest")}</h2>
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
