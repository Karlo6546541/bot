/**
 * Basic in-memory token bucket. Good enough for a single instance / MVP.
 * For multi-instance deployments swap the store for Redis/Upstash.
 */
interface Bucket {
  tokens: number;
  updated: number;
}

export interface RateLimitRule {
  /** max burst */
  capacity: number;
  /** tokens added per second */
  refillPerSec: number;
}

export function createRateLimiter(now: () => number = Date.now) {
  const buckets = new Map<string, Bucket>();
  return {
    take(key: string, rule: RateLimitRule): { ok: boolean; retryAfterSec: number } {
      const t = now();
      const b = buckets.get(key) ?? { tokens: rule.capacity, updated: t };
      const elapsed = (t - b.updated) / 1000;
      b.tokens = Math.min(rule.capacity, b.tokens + elapsed * rule.refillPerSec);
      b.updated = t;
      if (buckets.size > 50_000) buckets.clear(); // crude memory bound
      if (b.tokens < 1) {
        buckets.set(key, b);
        return { ok: false, retryAfterSec: Math.ceil((1 - b.tokens) / rule.refillPerSec) };
      }
      b.tokens -= 1;
      buckets.set(key, b);
      return { ok: true, retryAfterSec: 0 };
    },
  };
}

export const RULES = {
  api: { capacity: 60, refillPerSec: 1 }, // 60 burst, 60/min
  auth: { capacity: 10, refillPerSec: 0.1 }, // 10 burst, 6/min
  payments: { capacity: 10, refillPerSec: 0.2 },
} satisfies Record<string, RateLimitRule>;
