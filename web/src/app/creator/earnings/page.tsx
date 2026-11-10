import { getI18n } from "@/lib/i18n/server";
import { requireCreator } from "@/lib/auth/creator";
import { getMyEarnings } from "@/lib/earnings";
import { formatMoney } from "@/lib/format";

export default async function EarningsPage() {
  const viewer = await requireCreator("/creator/earnings");
  const { t, locale } = await getI18n();
  const rows = await getMyEarnings(viewer.id);
  const money = (c: number) => formatMoney(c, "EUR", locale);
  const monthName = (p: string) =>
    new Intl.DateTimeFormat("hr-HR", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(p));

  const months = [...new Set(rows.map((r) => r.period))];
  const bySeries = new Map<string, { title: string; gross: number; mine: number }>();
  for (const r of rows) {
    const k = r.seriesId ?? r.seriesTitle;
    const e = bySeries.get(k) ?? { title: r.seriesTitle, gross: 0, mine: 0 };
    e.gross += r.grossCents;
    e.mine += r.creatorCents;
    bySeries.set(k, e);
  }
  const total = rows.reduce((s, r) => s + r.creatorCents, 0);

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="h1">{t("creator.earningsTitle")}</h1>
        <a href="/api/creator/earnings.csv" className="btn-secondary" download>⬇ {t("creator.exportCsv")}</a>
      </div>
      <p className="muted text-sm">{t("creator.payoutNote")}</p>
      <p className="text-3xl font-black">{money(total)}</p>

      {rows.length === 0 ? (
        <p className="muted">{t("creator.noEarnings")}</p>
      ) : (
        <>
          <section aria-labelledby="per-series" className="overflow-x-auto">
            <h2 id="per-series" className="h2 mb-2">{t("creator.series")}</h2>
            <table className="table">
              <thead><tr><th>{t("creator.series")}</th><th className="text-right">{t("creator.gross")}</th><th className="text-right">{t("creator.yourShare")}</th></tr></thead>
              <tbody>
                {[...bySeries.values()].map((s) => (
                  <tr key={s.title}><td>{s.title}</td><td className="text-right tabular-nums">{money(s.gross)}</td><td className="text-right font-semibold tabular-nums">{money(s.mine)}</td></tr>
                ))}
              </tbody>
            </table>
          </section>

          {months.map((m) => {
            const mrows = rows.filter((r) => r.period === m);
            return (
              <section key={m} aria-label={monthName(m)} className="overflow-x-auto">
                <h2 className="h2 mb-2 capitalize">{monthName(m)}</h2>
                <table className="table">
                  <thead>
                    <tr><th>{t("creator.series")}</th><th>{t("creator.source")}</th><th className="text-right">{t("creator.gross")}</th><th className="text-right">{t("creator.yourShare")}</th></tr>
                  </thead>
                  <tbody>
                    {mrows.map((r) => (
                      <tr key={`${r.seriesId}-${r.source}`}>
                        <td>{r.seriesTitle}</td>
                        <td>{t(`creator.sources.${r.source}`)} <span className="muted">({r.items})</span></td>
                        <td className="text-right tabular-nums">{money(r.grossCents)}</td>
                        <td className="text-right font-semibold tabular-nums">{money(r.creatorCents)}</td>
                      </tr>
                    ))}
                    <tr><td colSpan={3} className="font-semibold">{t("creator.total")}</td><td className="text-right font-bold tabular-nums">{money(mrows.reduce((s, r) => s + r.creatorCents, 0))}</td></tr>
                  </tbody>
                </table>
              </section>
            );
          })}
        </>
      )}
    </div>
  );
}
