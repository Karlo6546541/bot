import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";

export default async function Forbidden() {
  const { t } = await getI18n();
  return (
    <div className="py-16 text-center">
      <h1 className="h1">{t("auth.forbidden")}</h1>
      <Link href="/" className="btn-primary mt-6">{t("common.goHome")}</Link>
    </div>
  );
}
