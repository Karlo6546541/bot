import { getI18n } from "@/lib/i18n/server";

const messages: Record<string, string> = {
  already_subscribed: "pricing.alreadySubscribed",
  invalid_session: "checkout.invalidSession",
  no_subscription: "account.noSubscription",
};

export async function PaymentErrorNotice({ code }: { code?: string }) {
  if (!code) return null;
  const { t } = await getI18n();
  const key = (messages[code] ?? "common.error") as Parameters<typeof t>[0];
  return (
    <p role="alert" className="rounded-lg bg-red-100 px-3 py-2 text-sm text-red-900 dark:bg-red-950 dark:text-red-100">
      {t(key)}
    </p>
  );
}
