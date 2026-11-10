"use client";
import { useActionState } from "react";
import { useI18n } from "@/lib/i18n/client";
import { FormMessage } from "@/components/forms/FormMessage";
import type { ActionState } from "@/app/creator/actions";

/** Generic form wrapper for (state, formData) server actions with status messages. */
export function ActionForm({
  action,
  submitLabel,
  children,
  className = "space-y-4",
}: {
  action: (prev: ActionState, fd: FormData) => Promise<ActionState>;
  submitLabel: string;
  children: React.ReactNode;
  className?: string;
}) {
  const { t } = useI18n();
  const [state, formAction, pending] = useActionState(action, undefined);
  return (
    <form action={formAction} className={className}>
      {children}
      <FormMessage error={state?.error} ok={state?.ok} />
      <button className="btn-primary" disabled={pending}>{pending ? t("common.loading") : submitLabel}</button>
    </form>
  );
}
