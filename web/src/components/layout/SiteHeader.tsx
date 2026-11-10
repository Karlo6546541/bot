import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import type { Viewer } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { logout } from "@/app/(auth)/actions";
import { CoinIcon } from "@/components/ui/Icons";

export async function SiteHeader({ viewer }: { viewer: Viewer | null }) {
  const { t } = await getI18n();
  let balance: number | null = null;
  if (viewer) {
    const supabase = await createClient();
    const { data } = await supabase.from("coin_balances").select("balance").eq("user_id", viewer.id).maybeSingle();
    balance = data?.balance ?? 0;
  }
  const role = viewer?.profile.role;
  const link = "rounded-md px-3 py-2 text-sm font-extrabold uppercase tracking-wide hover:bg-sun hover:text-ink-900";
  return (
    <header className="sticky top-0 z-30 border-b-2 bg-ink-50/95 backdrop-blur dark:bg-ink-950/95" style={{ borderColor: "var(--edge)" }}>
      <div className="mx-auto flex h-14 max-w-5xl items-center gap-3 px-4">
        <Link href="/" className="group flex items-center gap-2" aria-label={t("common.appName")}>
          <span
            aria-hidden
            className="grid h-9 w-9 -rotate-3 place-items-center rounded-md border-2 bg-brand-500 text-xl font-black text-white transition-transform group-hover:rotate-3"
            style={{ borderColor: "var(--edge)", boxShadow: "2px 2px 0 0 var(--edge)", fontFamily: "var(--font-display)" }}
          >
            K
          </span>
          <span className="text-xl font-black uppercase tracking-tight" style={{ fontFamily: "var(--font-display)" }}>
            {t("common.appName")}
          </span>
        </Link>
        <nav aria-label={t("nav.main")} className="ml-4 hidden items-center gap-1 sm:flex">
          <Link className={link} href="/browse">{t("nav.browse")}</Link>
          {viewer && <Link className={link} href="/library">{t("nav.library")}</Link>}
          <Link className={link} href="/pricing">{t("nav.pricing")}</Link>
          {(role === "creator" || role === "admin") && <Link className={link} href="/creator">{t("nav.creator")}</Link>}
          {role === "admin" && <Link className={link} href="/admin">{t("nav.admin")}</Link>}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          {viewer ? (
            <>
              <Link
                href="/pricing#coins"
                className="badge-early min-h-8 gap-1 px-2.5 py-1 text-sm"
                aria-label={t("account.balance", { coins: t("common.coinCount", { count: balance ?? 0 }) })}
              >
                <CoinIcon className="h-4 w-4" /> {balance}
              </Link>
              <Link className={`${link} hidden sm:inline-flex`} href="/account">{t("nav.account")}</Link>
              <form action={logout} className="hidden sm:block">
                <button className={link} type="submit">{t("nav.logout")}</button>
              </form>
            </>
          ) : (
            <>
              <Link className={link} href="/login">{t("nav.login")}</Link>
              <Link className="btn-primary hidden sm:inline-flex" href="/signup">{t("nav.signup")}</Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
