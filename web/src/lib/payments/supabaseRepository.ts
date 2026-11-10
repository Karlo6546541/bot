import "server-only";
import { createAdminClient, type AdminClient } from "@/lib/supabase/admin";
import { toAccessChapter, toAccessSeries } from "@/lib/access/mappers";
import { monetizationDefaults } from "@/config/monetization";
import type { Database } from "@/lib/supabase/database.types";
import type { PaymentRepository, Plan, SubscriptionRecord } from "./types";

type SubRow = Database["public"]["Tables"]["subscriptions"]["Row"];
type PlanRow = Database["public"]["Tables"]["pricing_plans"]["Row"];

const toPlan = (r: PlanRow): Plan => ({
  id: r.id,
  kind: r.kind,
  code: r.code,
  name: r.name,
  priceCents: r.price_cents,
  currency: r.currency,
  coins: r.coins,
  stripePriceId: r.stripe_price_id,
});

const toSub = (r: SubRow): SubscriptionRecord => ({
  id: r.id,
  userId: r.user_id,
  planId: r.plan_id,
  provider: r.provider,
  providerSubscriptionId: r.provider_subscription_id,
  providerCustomerId: r.provider_customer_id,
  status: r.status,
  currentPeriodStart: new Date(r.current_period_start),
  currentPeriodEnd: new Date(r.current_period_end),
  cancelAtPeriodEnd: r.cancel_at_period_end,
  canceledAt: r.canceled_at ? new Date(r.canceled_at) : null,
});

function check<T>(res: { data: T; error: { message: string } | null }, what: string): T {
  if (res.error) throw new Error(`${what}: ${res.error.message}`);
  return res.data;
}

/** Service-role implementation of the payment persistence port. */
export function createSupabasePaymentRepository(db: AdminClient = createAdminClient()): PaymentRepository {
  return {
    async getPlanByCode(code) {
      const { data } = await db.from("pricing_plans").select("*").eq("code", code).eq("active", true).maybeSingle();
      return data ? toPlan(data) : null;
    },
    async getPlanById(id) {
      const { data } = await db.from("pricing_plans").select("*").eq("id", id).maybeSingle();
      return data ? toPlan(data) : null;
    },
    async getSettings() {
      const { data } = await db.from("platform_settings").select("key, value").in("key", ["creator_share_pct", "coin_value_cents"]);
      const get = (k: string) => data?.find((r) => r.key === k)?.value;
      return {
        creatorSharePct: Number(get("creator_share_pct") ?? monetizationDefaults.creatorSharePct),
        coinValueCents: Number(get("coin_value_cents") ?? monetizationDefaults.coinValueCents),
      };
    },
    async getCreatorSharePct(creatorId) {
      const { data } = await db.from("creators").select("revenue_share_pct").eq("id", creatorId).maybeSingle();
      return data?.revenue_share_pct ?? null;
    },

    async claimEvent(provider, eventId, type) {
      return Boolean(
        check(await db.rpc("claim_payment_event", { p_provider: provider, p_event_id: eventId, p_type: type }), "claim"),
      );
    },
    async releaseEvent(provider, eventId) {
      check(await db.rpc("release_payment_event", { p_provider: provider, p_event_id: eventId }), "release");
    },

    async recordPayment(p) {
      const { data, error } = await db
        .from("payments")
        .upsert(
          {
            user_id: p.userId,
            kind: p.kind,
            plan_id: p.planId,
            provider: p.provider,
            provider_ref: p.providerRef,
            amount_cents: p.amountCents,
            currency: p.currency,
            period: p.period,
          },
          { onConflict: "provider_ref", ignoreDuplicates: true },
        )
        .select("id");
      if (error) throw new Error(`recordPayment: ${error.message}`);
      return (data?.length ?? 0) > 0;
    },

    async upsertSubscription(s) {
      const row = check(
        await db
          .from("subscriptions")
          .upsert(
            {
              user_id: s.userId,
              plan_id: s.planId,
              provider: s.provider,
              provider_subscription_id: s.providerSubscriptionId,
              provider_customer_id: s.providerCustomerId,
              status: s.status,
              current_period_start: s.currentPeriodStart.toISOString(),
              current_period_end: s.currentPeriodEnd.toISOString(),
              cancel_at_period_end: s.cancelAtPeriodEnd,
              canceled_at: s.canceledAt?.toISOString() ?? null,
            },
            { onConflict: "provider_subscription_id" },
          )
          .select()
          .single(),
        "upsertSubscription",
      );
      return toSub(row!);
    },
    async findSubscriptionByProviderId(id) {
      const { data } = await db.from("subscriptions").select("*").eq("provider_subscription_id", id).maybeSingle();
      return data ? toSub(data) : null;
    },
    async findActiveSubscription(userId, now) {
      const { data } = await db
        .from("subscriptions")
        .select("*")
        .eq("user_id", userId)
        .eq("status", "active")
        .gt("current_period_end", now.toISOString())
        .order("current_period_end", { ascending: false })
        .limit(1)
        .maybeSingle();
      return data ? toSub(data) : null;
    },
    async updateSubscription(id, patch) {
      const row: Database["public"]["Tables"]["subscriptions"]["Update"] = {};
      if (patch.status) row.status = patch.status;
      if (patch.cancelAtPeriodEnd !== undefined) row.cancel_at_period_end = patch.cancelAtPeriodEnd;
      if (patch.currentPeriodStart) row.current_period_start = patch.currentPeriodStart.toISOString();
      if (patch.currentPeriodEnd) row.current_period_end = patch.currentPeriodEnd.toISOString();
      if (patch.canceledAt !== undefined) row.canceled_at = patch.canceledAt?.toISOString() ?? null;
      if (patch.providerCustomerId !== undefined) row.provider_customer_id = patch.providerCustomerId;
      if (patch.planId !== undefined) row.plan_id = patch.planId;
      const { data, error } = await db.from("subscriptions").update(row).eq("provider_subscription_id", id).select().maybeSingle();
      if (error) throw new Error(`updateSubscription: ${error.message}`);
      return data ? toSub(data) : null;
    },

    async creditCoins(a) {
      const res = check(
        await db.rpc("apply_coin_credit", {
          p_user: a.userId,
          p_amount: a.amount,
          p_type: a.type,
          p_plan: a.planId ?? undefined,
          p_provider: a.provider ?? undefined,
          p_ref: a.ref ?? undefined,
          p_note: a.note ?? undefined,
        }),
        "creditCoins",
      ) as { status: "ok" | "duplicate"; balance: number };
      return res;
    },
    async getBalance(userId) {
      const { data } = await db.from("coin_balances").select("balance").eq("user_id", userId).maybeSingle();
      return data?.balance ?? 0;
    },

    async getChapterForUnlock(chapterId) {
      const { data } = await db.from("chapters").select("*, series(*)").eq("id", chapterId).maybeSingle();
      if (!data?.series) return null;
      return { chapter: toAccessChapter(data), series: { id: data.series.id, ...toAccessSeries(data.series) } };
    },
    async getAccessUser(userId, chapterIds, now) {
      const [profile, sub, unlocks] = await Promise.all([
        db.from("profiles").select("role").eq("id", userId).maybeSingle(),
        db
          .from("subscriptions")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("status", "active")
          .gt("current_period_end", now.toISOString()),
        db.from("chapter_unlocks").select("chapter_id").eq("user_id", userId).in("chapter_id", chapterIds),
      ]);
      if (!profile.data) return null;
      return {
        id: userId,
        role: profile.data.role,
        hasActiveSubscription: (sub.count ?? 0) > 0,
        unlockedChapterIds: new Set((unlocks.data ?? []).map((u) => u.chapter_id)),
      };
    },
    async applyChapterUnlock(a) {
      return check(
        await db.rpc("apply_chapter_unlock", {
          p_user: a.userId,
          p_chapter: a.chapterId,
          p_price: a.price,
          p_creator: a.creatorId,
          p_series: a.seriesId,
          p_gross_cents: a.grossCents,
          p_creator_cents: a.creatorCents,
          p_platform_cents: a.platformCents,
          p_share_pct: a.sharePct,
          p_period: a.period,
        }),
        "applyChapterUnlock",
      ) as { status: "unlocked" | "already_unlocked" | "insufficient_coins"; balance: number };
    },

    async getCustomerId(userId, provider) {
      const { data } = await db
        .from("billing_customers")
        .select("customer_id")
        .eq("user_id", userId)
        .eq("provider", provider)
        .maybeSingle();
      return data?.customer_id ?? null;
    },
    async saveCustomerId(userId, provider, customerId) {
      check(
        await db.from("billing_customers").upsert({ user_id: userId, provider, customer_id: customerId }),
        "saveCustomerId",
      );
    },

    async sumPayments(period, kind) {
      return Number(check(await db.rpc("sum_payments", { p_period: period, p_kind: kind }), "sumPayments") ?? 0);
    },
    async subscriptionReads(period) {
      const rows = check(await db.rpc("subscription_reads_by_series", { p_period: period }), "subscriptionReads") ?? [];
      return rows.map((r) => ({ creatorId: r.creator_id, seriesId: r.series_id, reads: Number(r.reads) }));
    },
    async insertEarnings(rows) {
      check(
        await db.from("creator_earnings").upsert(
          rows.map((r) => ({
            creator_id: r.creatorId,
            series_id: r.seriesId,
            chapter_id: r.chapterId,
            source: r.source,
            gross_cents: r.grossCents,
            creator_cents: r.creatorCents,
            platform_cents: r.platformCents,
            share_pct: r.sharePct,
            period: r.period,
            ref: r.ref,
          })),
          { onConflict: "source,ref,creator_id", ignoreDuplicates: true },
        ),
        "insertEarnings",
      );
    },
  };
}
