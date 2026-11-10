import Link from "next/link";
import { getI18n } from "@/lib/i18n/server";
import { formatDate } from "@/lib/format";
import type { AccessDecision } from "@/lib/access/canReadChapter";
import { UnlockButton } from "./UnlockButton";
import { LockIcon } from "@/components/ui/Icons";

type Denied = Extract<AccessDecision, { allowed: false }>;

export async function LockedChapter(props: {
  chapterId: string;
  seriesSlug: string;
  seriesTitle: string;
  chapterNumber: number;
  chapterTitle: string;
  decision: Denied;
  balance: number;
  loggedIn: boolean;
}) {
  const { t, locale } = await getI18n();
  const { decision } = props;
  const next = `/read/${props.chapterId}`;
  return (
    <section className="mx-auto max-w-md py-8 text-center" aria-labelledby="locked-title">
      <p className="muted text-sm">
        <Link href={`/series/${props.seriesSlug}`} className="underline">{props.seriesTitle}</Link> ·{" "}
        {t("series.chapterN", { n: props.chapterNumber })}
      </p>
      <div aria-hidden className="mx-auto mt-6 grid h-20 w-20 -rotate-3 place-items-center rounded-2xl border-2 bg-sun text-ink-900" style={{ borderColor: "var(--edge)", boxShadow: "4px 4px 0 0 var(--edge)" }}><LockIcon className="h-10 w-10" /></div>
      <h1 id="locked-title" className="h1 mt-3">{t("reader.lockedTitle")}</h1>
      <p className="muted mt-2">
        {decision.earlyAccessUntil
          ? t("reader.earlyText", { date: formatDate(decision.earlyAccessUntil, locale) })
          : t("reader.lockedText")}
      </p>

      {!props.loggedIn ? (
        <div className="mt-6 flex flex-col gap-2">
          <Link href={`/login?next=${encodeURIComponent(next)}`} className="btn-primary">{t("reader.loginToRead")}</Link>
          <Link href={`/signup?next=${encodeURIComponent(next)}`} className="btn-secondary">{t("nav.signup")}</Link>
        </div>
      ) : (
        <div className="mt-6 flex flex-col gap-3">
          <UnlockButton chapterId={props.chapterId} price={decision.coinPrice} balance={props.balance} />
          <p className="muted text-sm">
            {t("reader.yourBalance", { coins: t("common.coinCount", { count: props.balance }) })}
          </p>
          <div className="grid grid-cols-2 gap-2">
            <Link href="/pricing#coins" className="btn-secondary">{t("reader.buyCoins")}</Link>
            <Link href="/pricing" className="btn-secondary">{t("reader.subscribe")}</Link>
          </div>
        </div>
      )}
    </section>
  );
}
