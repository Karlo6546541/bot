"use client";
import { useActionState } from "react";
import { useI18n } from "@/lib/i18n/client";
import { unlockChapterAction, type UnlockState } from "@/app/payments/actions";
import { FormMessage } from "@/components/forms/FormMessage";

export function UnlockButton({ chapterId, price, balance }: { chapterId: string; price: number; balance: number }) {
  const { t } = useI18n();
  const [state, action, pending] = useActionState<UnlockState, FormData>(unlockChapterAction, undefined);
  const enough = balance >= price;
  return (
    <form action={action} className="space-y-2">
      <input type="hidden" name="chapterId" value={chapterId} />
      <button className="btn-primary w-full" disabled={pending || !enough}>
        {pending ? t("common.loading") : t("reader.unlockFor", { coins: t("common.coinCount", { count: price }) })}
      </button>
      {!enough && <p className="text-sm text-amber-700 dark:text-amber-400">{t("reader.insufficientCoins")}</p>}
      <FormMessage error={state?.error} />
    </form>
  );
}
