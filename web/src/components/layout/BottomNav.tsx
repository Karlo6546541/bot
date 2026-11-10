"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useI18n } from "@/lib/i18n/client";
import type { MessageKey } from "@/lib/i18n";

type Item = { href: string; label: MessageKey; icon: string };

export function BottomNav({ loggedIn, role }: { loggedIn: boolean; role: string | null }) {
  const { t } = useI18n();
  const pathname = usePathname();
  if (pathname.startsWith("/read/")) return null; // the reader is full-screen

  const items: Item[] = [
    { href: "/", label: "nav.home", icon: "⌂" },
    { href: "/browse", label: "nav.browse", icon: "⌕" },
    loggedIn ? { href: "/library", label: "nav.library", icon: "▤" } : { href: "/pricing", label: "nav.pricing", icon: "★" },
    role === "creator" || role === "admin"
      ? { href: "/creator", label: "nav.creator", icon: "✎" }
      : { href: loggedIn ? "/pricing" : "/signup", label: loggedIn ? "nav.pricing" : "nav.signup", icon: "★" },
    { href: loggedIn ? "/account" : "/login", label: loggedIn ? "nav.account" : "nav.login", icon: "◉" },
  ];
  const unique = items.filter((it, i) => items.findIndex((x) => x.href === it.href) === i);

  return (
    <nav
      aria-label={t("nav.main")}
      className="fixed inset-x-0 bottom-0 z-30 border-t border-ink-100 bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur sm:hidden dark:border-ink-800 dark:bg-ink-950/95"
    >
      <ul className="flex">
        {unique.map((it) => {
          const active = it.href === "/" ? pathname === "/" : pathname.startsWith(it.href);
          return (
            <li key={it.href} className="flex-1">
              <Link
                href={it.href}
                aria-current={active ? "page" : undefined}
                className={`flex min-h-14 flex-col items-center justify-center text-xs ${active ? "font-bold text-brand-600" : "text-ink-500 dark:text-ink-400"}`}
              >
                <span aria-hidden className="text-lg leading-none">{it.icon}</span>
                {t(it.label)}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
