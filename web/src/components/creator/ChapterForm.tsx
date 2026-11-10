"use client";
import { useActionState, useState } from "react";
import { useI18n } from "@/lib/i18n/client";
import { FormMessage } from "@/components/forms/FormMessage";
import type { ActionState } from "@/app/creator/actions";

export interface ChapterDefaults {
  number: number;
  title: string;
  access: "free" | "locked" | "early_access";
  coinPrice: number;
  earlyDays: number;
  publishAt: string | null; // ISO
  published: boolean;
}

/** ISO -> value for <input type="datetime-local"> in the browser's timezone. */
function toLocalInput(iso: string | null) {
  const d = iso ? new Date(iso) : new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function ChapterForm({
  action,
  defaults,
}: {
  action: (prev: ActionState, fd: FormData) => Promise<ActionState>;
  defaults: ChapterDefaults;
}) {
  const { t } = useI18n();
  const [access, setAccess] = useState(defaults.access);
  const [local, setLocal] = useState(toLocalInput(defaults.publishAt));
  const [state, formAction, pending] = useActionState(action, undefined);
  const iso = local ? new Date(local).toISOString() : "";

  return (
    <form action={formAction} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-[140px_1fr]">
        <div>
          <label className="label" htmlFor="number">{t("creator.chapterNumber")}</label>
          <input className="input" id="number" name="number" type="number" min={1} required defaultValue={defaults.number} />
        </div>
        <div>
          <label className="label" htmlFor="title">{t("creator.chapterTitle")}</label>
          <input className="input" id="title" name="title" maxLength={120} defaultValue={defaults.title} />
        </div>
      </div>
      <fieldset>
        <legend className="label">{t("creator.access")}</legend>
        <div className="grid gap-2 sm:grid-cols-3">
          {(["free", "locked", "early_access"] as const).map((a) => (
            <label key={a} className="flex min-h-11 items-center gap-2 rounded-lg border border-ink-200 px-3 dark:border-ink-700">
              <input type="radio" name="access" value={a} checked={access === a} onChange={() => setAccess(a)} />
              {t(a === "free" ? "creator.accessFree" : a === "locked" ? "creator.accessLocked" : "creator.accessEarly")}
            </label>
          ))}
        </div>
      </fieldset>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="label" htmlFor="coin_price">{t("creator.coinPrice")}</label>
          <input className="input" id="coin_price" name="coin_price" type="number" min={0} max={10000} defaultValue={defaults.coinPrice} />
        </div>
        {access === "early_access" && (
          <div>
            <label className="label" htmlFor="early_days">{t("creator.earlyDays")}</label>
            <input className="input" id="early_days" name="early_days" type="number" min={1} max={365} required defaultValue={defaults.earlyDays} />
          </div>
        )}
      </div>
      <div>
        <label className="label" htmlFor="publish_local">{t("creator.publishAt")}</label>
        <input className="input" id="publish_local" type="datetime-local" value={local} onChange={(e) => setLocal(e.target.value)} />
        <input type="hidden" name="publish_at" value={iso} />
      </div>
      <label className="flex min-h-11 items-center gap-2">
        <input type="checkbox" name="published" defaultChecked={defaults.published} />
        {t("creator.published")}
      </label>
      <FormMessage error={state?.error} ok={state?.ok} />
      <button className="btn-primary" disabled={pending}>{pending ? t("common.loading") : t("common.save")}</button>
    </form>
  );
}
