import { NextResponse } from "next/server";
import { getViewer } from "@/lib/auth/session";
import { checkChapterAccess, signChapterPages } from "@/lib/access/server";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Fresh signed URLs for a chapter — only after a server-side access check. */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) return NextResponse.json({ error: "not_found" }, { status: 404 });
  const viewer = await getViewer();
  const ctx = await checkChapterAccess(id, viewer ? { id: viewer.id, role: viewer.profile.role } : null);
  if (!ctx) return NextResponse.json({ error: "not_found" }, { status: 404 });
  if (!ctx.decision.allowed) {
    return NextResponse.json({ error: ctx.decision.reason }, { status: ctx.decision.reason === "login_required" ? 401 : 403 });
  }
  const signed = await signChapterPages(id);
  return NextResponse.json(signed, { headers: { "Cache-Control": "private, no-store" } });
}
