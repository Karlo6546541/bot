import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { createRateLimiter, RULES, type RateLimitRule } from "@/lib/rateLimit";

const limiter = createRateLimiter();

function ruleFor(req: NextRequest): [string, RateLimitRule] | null {
  const p = req.nextUrl.pathname;
  if (p.startsWith("/api/webhooks/")) return null; // provider retries must not be throttled
  if (req.method === "POST" && (p.startsWith("/login") || p.startsWith("/signup"))) return ["auth", RULES.auth];
  if (p.startsWith("/api/payments") || p.startsWith("/checkout")) return ["payments", RULES.payments];
  if (p.startsWith("/api/")) return ["api", RULES.api];
  return null;
}

export async function middleware(req: NextRequest) {
  const rule = ruleFor(req);
  if (rule) {
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || req.headers.get("x-real-ip") || "local";
    const r = limiter.take(`${rule[0]}:${ip}`, rule[1]);
    if (!r.ok) {
      return new NextResponse("Previše zahtjeva.", {
        status: 429,
        headers: { "Retry-After": String(r.retryAfterSec), "Content-Type": "text/plain; charset=utf-8" },
      });
    }
  }

  // Refresh the Supabase session cookie.
  let res = NextResponse.next({ request: req });
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => req.cookies.getAll(),
        setAll: (toSet) => {
          for (const { name, value } of toSet) req.cookies.set(name, value);
          res = NextResponse.next({ request: req });
          for (const { name, value, options } of toSet) res.cookies.set(name, value, options);
        },
      },
    },
  );
  await supabase.auth.getUser();
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icons/|manifest.webmanifest|sw.js|.*\\.(?:png|jpg|svg|webp)$).*)"],
};
