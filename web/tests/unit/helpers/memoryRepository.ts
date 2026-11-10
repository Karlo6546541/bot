/** In-memory PaymentRepository with the same semantics as the SQL functions. */
import type { AccessChapter, AccessSeries } from "@/lib/access/canReadChapter";
import type {
  CoinCreditArgs,
  EarningRecord,
  PaymentRecord,
  PaymentRepository,
  Plan,
  SubscriptionRecord,
} from "@/lib/payments/types";

export const PLANS: Plan[] = [
  { id: "plan-sub", kind: "subscription", code: "monthly", name: "Mjesečna", priceCents: 499, currency: "EUR", coins: null, stripePriceId: "price_sub" },
  { id: "plan-c50", kind: "coin_pack", code: "coins_50", name: "50", priceCents: 499, currency: "EUR", coins: 50, stripePriceId: "price_c50" },
  { id: "plan-c120", kind: "coin_pack", code: "coins_120", name: "120", priceCents: 999, currency: "EUR", coins: 120, stripePriceId: null },
];

export function createMemoryRepository() {
  const state = {
    plans: [...PLANS],
    settings: { creatorSharePct: 65, coinValueCents: 10 },
    creatorShare: new Map<string, number>(),
    events: new Set<string>(),
    payments: [] as PaymentRecord[],
    subs: [] as SubscriptionRecord[],
    balances: new Map<string, number>(),
    coinTx: [] as (CoinCreditArgs & { amount: number })[],
    unlocks: new Set<string>(),
    unlockTx: [] as { userId: string; chapterId: string; price: number }[],
    earnings: [] as EarningRecord[],
    users: new Map<string, { role: "reader" | "creator" | "admin" }>(),
    chapters: new Map<string, { chapter: AccessChapter; series: AccessSeries & { id: string } }>(),
    customers: new Map<string, string>(),
    reads: [] as { creatorId: string; seriesId: string; period: string }[],
  };
  let n = 0;

  const repo: PaymentRepository = {
    async getPlanByCode(code) {
      return state.plans.find((p) => p.code === code) ?? null;
    },
    async getPlanById(id) {
      return state.plans.find((p) => p.id === id) ?? null;
    },
    async getSettings() {
      return state.settings;
    },
    async getCreatorSharePct(id) {
      return state.creatorShare.get(id) ?? null;
    },
    async claimEvent(p, id) {
      const k = `${p}:${id}`;
      if (state.events.has(k)) return false;
      state.events.add(k);
      return true;
    },
    async releaseEvent(p, id) {
      state.events.delete(`${p}:${id}`);
    },
    async recordPayment(p) {
      if (state.payments.some((x) => x.providerRef === p.providerRef)) return false;
      state.payments.push(p);
      return true;
    },
    async upsertSubscription(s) {
      const i = state.subs.findIndex((x) => x.providerSubscriptionId === s.providerSubscriptionId);
      const rec = { ...(i >= 0 ? state.subs[i] : { id: `sub-${++n}` }), ...s } as SubscriptionRecord;
      if (i >= 0) state.subs[i] = rec;
      else state.subs.push(rec);
      return rec;
    },
    async findSubscriptionByProviderId(id) {
      return state.subs.find((s) => s.providerSubscriptionId === id) ?? null;
    },
    async findActiveSubscription(userId, now) {
      return (
        state.subs
          .filter((s) => s.userId === userId && s.status === "active" && s.currentPeriodEnd > now)
          .sort((a, b) => +b.currentPeriodEnd - +a.currentPeriodEnd)[0] ?? null
      );
    },
    async updateSubscription(id, patch) {
      const s = state.subs.find((x) => x.providerSubscriptionId === id);
      if (!s) return null;
      Object.assign(s, Object.fromEntries(Object.entries(patch).filter(([, v]) => v !== undefined)));
      return s;
    },
    async creditCoins(a) {
      if (a.ref && state.coinTx.some((t) => t.type === a.type && t.ref === a.ref)) {
        return { status: "duplicate", balance: state.balances.get(a.userId) ?? 0 };
      }
      const bal = (state.balances.get(a.userId) ?? 0) + a.amount;
      if (bal < 0) throw new Error("balance check violated");
      state.balances.set(a.userId, bal);
      state.coinTx.push(a);
      return { status: "ok", balance: bal };
    },
    async getBalance(u) {
      return state.balances.get(u) ?? 0;
    },
    async getChapterForUnlock(id) {
      return state.chapters.get(id) ?? null;
    },
    async getAccessUser(userId, chapterIds, now) {
      const u = state.users.get(userId);
      if (!u) return null;
      return {
        id: userId,
        role: u.role,
        hasActiveSubscription: !!(await repo.findActiveSubscription(userId, now)),
        unlockedChapterIds: new Set(chapterIds.filter((c) => state.unlocks.has(`${userId}:${c}`))),
      };
    },
    async applyChapterUnlock(a) {
      const key = `${a.userId}:${a.chapterId}`;
      const bal = state.balances.get(a.userId) ?? 0;
      if (state.unlocks.has(key)) return { status: "already_unlocked", balance: bal };
      if (bal < a.price) return { status: "insufficient_coins", balance: bal };
      state.balances.set(a.userId, bal - a.price);
      state.unlocks.add(key);
      state.unlockTx.push({ userId: a.userId, chapterId: a.chapterId, price: a.price });
      if (a.grossCents > 0) {
        state.earnings.push({
          creatorId: a.creatorId,
          seriesId: a.seriesId,
          chapterId: a.chapterId,
          source: "coin_unlock",
          grossCents: a.grossCents,
          creatorCents: a.creatorCents,
          platformCents: a.platformCents,
          sharePct: a.sharePct,
          period: a.period,
          ref: `unlock:${key}`,
        });
      }
      return { status: "unlocked", balance: bal - a.price };
    },
    async getCustomerId(u, p) {
      return state.customers.get(`${p}:${u}`) ?? null;
    },
    async saveCustomerId(u, p, c) {
      state.customers.set(`${p}:${u}`, c);
    },
    async sumPayments(period, kind) {
      return state.payments.filter((p) => p.period === period && p.kind === kind).reduce((s, p) => s + p.amountCents, 0);
    },
    async subscriptionReads(period) {
      const m = new Map<string, { creatorId: string; seriesId: string; reads: number }>();
      for (const r of state.reads.filter((x) => x.period === period)) {
        const e = m.get(r.seriesId) ?? { creatorId: r.creatorId, seriesId: r.seriesId, reads: 0 };
        e.reads++;
        m.set(r.seriesId, e);
      }
      return [...m.values()];
    },
    async insertEarnings(rows) {
      for (const r of rows) {
        if (!state.earnings.some((e) => e.source === r.source && e.ref === r.ref && e.creatorId === r.creatorId)) {
          state.earnings.push(r);
        }
      }
    },
  };
  return { repo, state };
}

export const DAY = 86_400_000;

/** Adds a published series (free_chapters=3) with a locked chapter #5. */
export function seedChapter(
  state: ReturnType<typeof createMemoryRepository>["state"],
  o: { chapterId?: string; creatorId?: string; seriesId?: string; price?: number; number?: number; now?: Date } = {},
) {
  const now = o.now ?? new Date("2026-11-10T12:00:00Z");
  const chapterId = o.chapterId ?? "ch-5";
  state.users.set(o.creatorId ?? "creator-1", { role: "creator" });
  state.chapters.set(chapterId, {
    chapter: {
      id: chapterId,
      number: o.number ?? 5,
      access: "locked",
      coinPrice: o.price ?? 5,
      published: true,
      publishAt: new Date(now.getTime() - DAY),
      earlyAccessUntil: null,
    },
    series: { id: o.seriesId ?? "series-1", creatorId: o.creatorId ?? "creator-1", status: "published", hiddenByAdmin: false, freeChapters: 3 },
  });
  return chapterId;
}
