import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";

export const metadata = { robots: { index: false } };

export default async function Page() {
  const { t } = await getI18n();
  return (
    <section className="mx-auto max-w-md py-16 text-center" role="status">
      <h1 className="h1">{t("checkout.canceledTitle")}</h1>
      <p className="muted mt-2">{t("checkout.failedText")}</p>
      <Link href="/pricing" className="btn-primary mt-6">{t("checkout.continue")}</Link>
    </section>
  );
}
