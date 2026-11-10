"use client";
import { useActionState } from "react";
import { useI18n } from "@/lib/i18n/client";
import { FormMessage } from "@/components/forms/FormMessage";
import type { MessageKey } from "@/lib/i18n";

type FormState = { error?: MessageKey; ok?: MessageKey; okParams?: Record<string, string | number> } | undefined;

/** Generic form wrapper for (state, formData) server actions with status messages. */
export function ActionForm({
  action,
  submitLabel,
  children,
  className = "space-y-4",
}: {
  action: (prev: FormState, fd: FormData) => Promise<FormState>;
  submitLabel: string;
  children: React.ReactNode;
  className?: string;
}) {
  const { t } = useI18n();
  const [state, formAction, pending] = useActionState(action, undefined);
  return (
    <form action={formAction} className={className}>
      {children}
      <FormMessage error={state?.error} ok={state?.ok} params={state?.okParams} />
      <button className="btn-primary" disabled={pending}>{pending ? t("common.loading") : submitLabel}</button>
    </form>
  );
}
