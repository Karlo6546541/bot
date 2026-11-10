"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useI18n } from "@/lib/i18n/client";
import type { MessageKey } from "@/lib/i18n";
import { HomeIcon, LibraryIcon, PenIcon, SearchIcon, StarIcon, UserIcon } from "@/components/ui/Icons";

type Item = { href: string; label: MessageKey; Icon: (p: { className?: string }) => React.ReactElement };

export function BottomNav({ loggedIn, role }: { loggedIn: boolean; role: string | null }) {
  const { t } = useI18n();
  const pathname = usePathname();
  if (pathname.startsWith("/read/")) return null; // the reader is full-screen

  const items: Item[] = [
    { href: "/", label: "nav.home", Icon: HomeIcon },
    { href: "/browse", label: "nav.browse", Icon: SearchIcon },
    loggedIn
      ? { href: "/library", label: "nav.library", Icon: LibraryIcon }
      : { href: "/pricing", label: "nav.pricing", Icon: StarIcon },
    role === "creator" || role === "admin"
      ? { href: "/creator", label: "nav.creator", Icon: PenIcon }
      : { href: "/pricing", label: "nav.pricing", Icon: StarIcon },
    { href: loggedIn ? "/account" : "/login", label: loggedIn ? "nav.account" : "nav.login", Icon: UserIcon },
  ];
  const unique = items.filter((it, i) => items.findIndex((x) => x.href === it.href) === i);

  return (
    <nav
      aria-label={t("nav.main")}
      className="fixed inset-x-0 bottom-0 z-30 border-t-2 bg-ink-50/95 pb-[env(safe-area-inset-bottom)] backdrop-blur sm:hidden dark:bg-ink-950/95"
      style={{ borderColor: "var(--edge)" }}
    >
      <ul className="flex">
        {unique.map(({ href, label, Icon }) => {
          const active = href === "/" ? pathname === "/" : pathname.startsWith(href);
          return (
            <li key={href} className="flex-1">
              <Link
                href={href}
                aria-current={active ? "page" : undefined}
                className="flex min-h-14 flex-col items-center justify-center gap-0.5 text-[11px] font-extrabold uppercase tracking-wide"
              >
                <span
                  className={`grid h-8 w-12 place-items-center rounded-full border-2 transition-colors ${active ? "bg-sun text-ink-900" : "border-transparent"}`}
                  style={active ? { borderColor: "var(--edge)" } : undefined}
                >
                  <Icon className="h-5 w-5" />
                </span>
                {t(label)}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
