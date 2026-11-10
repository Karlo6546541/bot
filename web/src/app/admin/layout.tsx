import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { requireAdmin } from "@/lib/auth/session";
import { isMockPayments } from "@/lib/payments";

export const metadata = { robots: { index: false } };

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await requireAdmin();
  const { t } = await getI18n();
  const links = [
    ["/admin", t("admin.stats")],
    ["/admin/creators", t("admin.applications")],
    ["/admin/series", t("admin.moderation")],
    ["/admin/settings", t("admin.settings")],
    ...(isMockPayments() ? [["/admin/test-tools", t("admin.testTools")]] : []),
  ];
  return (
    <div className="space-y-6">
      <h1 className="h1">{t("admin.title")}</h1>
      <nav aria-label={t("admin.title")} className="-mx-1 flex gap-1 overflow-x-auto">
        {links.map(([href, label]) => (
          <Link key={href} href={href} className="btn-ghost shrink-0">{label}</Link>
        ))}
      </nav>
      {children}
    </div>
  );
}
