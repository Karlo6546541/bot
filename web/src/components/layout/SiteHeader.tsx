import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import type { Viewer } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { logout } from "@/app/(auth)/actions";

export async function SiteHeader({ viewer }: { viewer: Viewer | null }) {
  const { t } = await getI18n();
  let balance: number | null = null;
  if (viewer) {
    const supabase = await createClient();
    const { data } = await supabase.from("coin_balances").select("balance").eq("user_id", viewer.id).maybeSingle();
    balance = data?.balance ?? 0;
  }
  const role = viewer?.profile.role;
  return (
    <header className="sticky top-0 z-30 border-b border-ink-100 bg-white/90 backdrop-blur dark:border-ink-800 dark:bg-ink-950/90">
      <div className="mx-auto flex h-14 max-w-5xl items-center gap-3 px-4">
        <Link href="/" className="text-lg font-black tracking-tight text-brand-600">
          {t("common.appName")}
        </Link>
        <nav aria-label={t("nav.main")} className="ml-4 hidden items-center gap-1 sm:flex">
          <Link className="btn-ghost" href="/browse">{t("nav.browse")}</Link>
          {viewer && <Link className="btn-ghost" href="/library">{t("nav.library")}</Link>}
          <Link className="btn-ghost" href="/pricing">{t("nav.pricing")}</Link>
          {(role === "creator" || role === "admin") && (
            <Link className="btn-ghost" href="/creator">{t("nav.creator")}</Link>
          )}
          {role === "admin" && <Link className="btn-ghost" href="/admin">{t("nav.admin")}</Link>}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          {viewer ? (
            <>
              <Link
                href="/pricing#coins"
                className="badge-early min-h-8"
                aria-label={t("account.balance", { coins: t("common.coinCount", { count: balance ?? 0 }) })}
              >
                🪙 {balance}
              </Link>
              <Link className="btn-ghost hidden sm:inline-flex" href="/account">{t("nav.account")}</Link>
              <form action={logout} className="hidden sm:block">
                <button className="btn-ghost" type="submit">{t("nav.logout")}</button>
              </form>
            </>
          ) : (
            <>
              <Link className="btn-ghost" href="/login">{t("nav.login")}</Link>
              <Link className="btn-primary hidden sm:inline-flex" href="/signup">{t("nav.signup")}</Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
