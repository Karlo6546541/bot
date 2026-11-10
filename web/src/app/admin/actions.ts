"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { getMockProvider, getPaymentService } from "@/lib/payments";
import type { MessageKey } from "@/lib/i18n";

export type AdminState = { error?: MessageKey; ok?: MessageKey; okParams?: Record<string, string | number> } | undefined;

// All admin writes use the service role AFTER assertAdmin() — never before.

export async function reviewCreator(creatorId: string, decision: "approved" | "rejected") {
  const admin = await assertAdmin();
  const db = createAdminClient();
  await db
    .from("creators")
    .update({ status: decision, reviewed_by: admin.id, reviewed_at: new Date().toISOString() })
    .eq("id", creatorId);
  const { data: profile } = await db.from("profiles").select("role").eq("id", creatorId).single();
  if (profile?.role !== "admin") {
    await db.from("profiles").update({ role: decision === "approved" ? "creator" : "reader" }).eq("id", creatorId);
  }
  revalidatePath("/admin/creators");
}

export async function setSeriesHidden(seriesId: string, hidden: boolean, fd: FormData) {
  await assertAdmin();
  const note = String(fd.get("note") ?? "").slice(0, 500) || null;
  await createAdminClient()
    .from("series")
    .update({ hidden_by_admin: hidden, moderation_note: hidden ? note : null })
    .eq("id", seriesId);
  revalidatePath("/admin/series");
  revalidatePath("/", "layout");
}

const settingsSchema = z.object({
  creator_share_pct: z.coerce.number().min(0).max(100),
  coin_value_cents: z.coerce.number().int().min(1).max(10000),
});

export async function saveSettings(_p: AdminState, fd: FormData): Promise<AdminState> {
  await assertAdmin();
  const parsed = settingsSchema.safeParse(Object.fromEntries(fd));
  if (!parsed.success) return { error: "errors.invalidInput" };
  const now = new Date().toISOString();
  await createAdminClient()
    .from("platform_settings")
    .upsert(Object.entries(parsed.data).map(([key, value]) => ({ key, value, updated_at: now })));
  revalidatePath("/admin/settings");
  return { ok: "common.saved" };
}

const planSchema = z.object({
  price_cents: z.coerce.number().int().min(1).max(1_000_000),
  coins: z.coerce.number().int().min(1).max(1_000_000).optional(),
  stripe_price_id: z.string().trim().max(100),
  active: z.boolean(),
});

export async function savePlan(planId: string, _p: AdminState, fd: FormData): Promise<AdminState> {
  await assertAdmin();
  const parsed = planSchema.safeParse({
    price_cents: fd.get("price_cents"),
    coins: fd.get("coins") || undefined,
    stripe_price_id: fd.get("stripe_price_id") ?? "",
    active: fd.get("active") === "on",
  });
  if (!parsed.success) return { error: "errors.invalidInput" };
  const { stripe_price_id, coins, ...rest } = parsed.data;
  const { error } = await createAdminClient()
    .from("pricing_plans")
    .update({ ...rest, ...(coins !== undefined && { coins }), stripe_price_id: stripe_price_id || null })
    .eq("id", planId);
  if (error) return { error: "errors.invalidInput" };
  revalidatePath("/admin/settings");
  return { ok: "common.saved" };
}

export async function distributePool(_p: AdminState, fd: FormData): Promise<AdminState> {
  await assertAdmin();
  const month = z.string().regex(/^\d{4}-\d{2}$/).safeParse(fd.get("month"));
  if (!month.success) return { error: "errors.invalidInput" };
  const res = await getPaymentService().service.distributeSubscriptionPool(`${month.data}-01`);
  if (res.status === "already_distributed") return { error: "admin.poolAlready" };
  return { ok: "admin.poolDone", okParams: { count: res.rows } };
}

// ----------------------------------------------------------------- mock-only test tools
async function userIdByEmail(email: FormDataEntryValue | null) {
  const { data } = await createAdminClient().rpc("admin_find_user_by_email", { p_email: String(email ?? "") });
  return data ?? null;
}

export async function grantCoinsAction(_p: AdminState, fd: FormData): Promise<AdminState> {
  await assertAdmin();
  if (!(await getMockProvider())) return { error: "admin.testToolsOnlyMock" };
  const amount = z.coerce.number().int().min(-100000).max(100000).refine((n) => n !== 0).safeParse(fd.get("amount"));
  if (!amount.success) return { error: "errors.invalidInput" };
  const userId = await userIdByEmail(fd.get("email"));
  if (!userId) return { error: "admin.userNotFound" };
  try {
    await getPaymentService().service.grantCoins(userId, amount.data, "admin test grant");
  } catch {
    return { error: "errors.invalidInput" }; // e.g. would make the balance negative
  }
  revalidatePath("/", "layout");
  return { ok: "admin.done" };
}

export async function grantSubscriptionAction(_p: AdminState, fd: FormData): Promise<AdminState> {
  await assertAdmin();
  if (!(await getMockProvider())) return { error: "admin.testToolsOnlyMock" };
  const days = z.coerce.number().int().min(1).max(3650).safeParse(fd.get("days"));
  if (!days.success) return { error: "errors.invalidInput" };
  const userId = await userIdByEmail(fd.get("email"));
  if (!userId) return { error: "admin.userNotFound" };
  await getPaymentService().service.grantSubscription(userId, days.data);
  revalidatePath("/", "layout");
  return { ok: "admin.done" };
}
