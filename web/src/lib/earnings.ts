import "server-only";
import { createClient } from "@/lib/supabase/server";

export interface EarningsRow {
  period: string;
  seriesId: string | null;
  seriesTitle: string;
  source: "coin_unlock" | "subscription_pool";
  items: number;
  grossCents: number;
  creatorCents: number;
  platformCents: number;
}

/** Caller's own earnings (RLS), aggregated per month / series / source. */
export async function getMyEarnings(creatorId: string): Promise<EarningsRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("earnings_summary", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return (data ?? []).map((r) => ({
    period: r.period,
    seriesId: r.series_id,
    seriesTitle: r.series_title,
    source: r.source,
    items: Number(r.items),
    grossCents: Number(r.gross_cents),
    creatorCents: Number(r.creator_cents),
    platformCents: Number(r.platform_cents),
  }));
}

/** CSV for Croatian Excel: ';' separator, decimal comma, UTF-8 BOM. */
export function earningsCsv(rows: EarningsRow[], labels: Record<EarningsRow["source"], string>): string {
  const money = (c: number) => (c / 100).toFixed(2).replace(".", ",");
  const esc = (s: string) => (/[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);
  const header = ["mjesec", "serija", "izvor", "broj_stavki", "bruto_eur", "kreator_eur", "platforma_eur"];
  const lines = rows.map((r) =>
    [r.period.slice(0, 7), esc(r.seriesTitle), labels[r.source], r.items, money(r.grossCents), money(r.creatorCents), money(r.platformCents)].join(";"),
  );
  return "﻿" + [header.join(";"), ...lines].join("\r\n") + "\r\n";
}
