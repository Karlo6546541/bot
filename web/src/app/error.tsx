"use client";
import { useI18n } from "@/lib/i18n/client";

export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  const { t } = useI18n();
  return (
    <div role="alert" className="py-16 text-center">
      <h1 className="h1">{t("common.error")}</h1>
      <button className="btn-primary mt-6" onClick={reset}>{t("reader.retry")}</button>
    </div>
  );
}
