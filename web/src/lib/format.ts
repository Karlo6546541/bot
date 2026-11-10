import { DEFAULT_LOCALE, type Locale } from "@/lib/i18n";

const intlLocale: Record<Locale, string> = { hr: "hr-HR" };

export function formatMoney(cents: number, currency = "EUR", locale: Locale = DEFAULT_LOCALE) {
  return new Intl.NumberFormat(intlLocale[locale], { style: "currency", currency }).format(cents / 100);
}

export function formatDate(d: string | Date, locale: Locale = DEFAULT_LOCALE) {
  return new Intl.DateTimeFormat(intlLocale[locale], { dateStyle: "medium" }).format(new Date(d));
}

export function formatDateTime(d: string | Date, locale: Locale = DEFAULT_LOCALE) {
  return new Intl.DateTimeFormat(intlLocale[locale], { dateStyle: "medium", timeStyle: "short" }).format(
    new Date(d),
  );
}

/** First day of the month (UTC) as YYYY-MM-DD — the accounting period. */
export function periodOf(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-01`;
}

/** "Čudo u Zagrebu!" -> "cudo-u-zagrebu" */
export function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/đ/g, "d")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

/** Normalise a search query the same way the DB normalises search_text. */
export function normalizeSearch(input: string): string {
  return input
    .toLowerCase()
    .replace(/đ/g, "d")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[%_,()\\]/g, " ")
    .trim()
    .slice(0, 80);
}
