"use client";
import { useI18n } from "@/lib/i18n/client";
import type { MessageKey } from "@/lib/i18n";

export function FormMessage({ error, ok }: { error?: MessageKey; ok?: MessageKey }) {
  const { t } = useI18n();
  if (!error && !ok) return <div aria-live="polite" />;
  return (
    <p
      role={error ? "alert" : "status"}
      aria-live="polite"
      className={`rounded-lg px-3 py-2 text-sm ${error ? "bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-100" : "bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100"}`}
    >
      {t(error ?? ok!)}
    </p>
  );
}
