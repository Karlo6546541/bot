import { getViewer } from "@/lib/auth/session";
import { earningsCsv, getMyEarnings } from "@/lib/earnings";
import { getI18n } from "@/lib/i18n/server";

export async function GET() {
  const viewer = await getViewer();
  if (!viewer) return new Response("Unauthorized", { status: 401 });
  const { messages } = await getI18n();
  const csv = earningsCsv(await getMyEarnings(viewer.id), messages.creator.sources);
  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="kadar-zarada-${new Date().toISOString().slice(0, 10)}.csv"`,
      "Cache-Control": "private, no-store",
    },
  });
}
