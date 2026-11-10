/**
 * Minimal, dependency-free i18n.
 *
 * Adding a language:
 *   1. copy messages/hr.ts to messages/<code>.ts and translate (the type
 *      `Messages` forces every key to exist),
 *   2. add it to `dictionaries` and `LOCALES` below,
 *   3. add an Intl locale in src/lib/format.ts.
 * The active locale comes from the `locale` cookie (falls back to hr).
 */
import { hr } from "./messages/hr";

export type Messages = typeof hr;
export const LOCALES = ["hr"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "hr";

export const dictionaries: Record<Locale, Messages> = { hr };

/** Croatian needs three plural forms; Intl.PluralRules picks one/few/other. */
export type PluralForms = { one: string; few: string; other: string };

type Join<K, P> = K extends string ? (P extends string ? `${K}.${P}` : never) : never;
export type MessageKey<T = Messages> = {
  [K in keyof T & string]: T[K] extends string ? K : T[K] extends PluralForms ? K : Join<K, MessageKey<T[K]>>;
}[keyof T & string];

export type Params = Record<string, string | number>;
export type TFunction = (key: MessageKey, params?: Params) => string;

export function isLocale(v: unknown): v is Locale {
  return typeof v === "string" && (LOCALES as readonly string[]).includes(v);
}

const intlTag: Record<Locale, string> = { hr: "hr-HR" };

/** Pass `{ count }` to a plural key: t("common.coinCount", { count: 3 }) -> "3 novčića" */
export function createT(messages: Messages, locale: Locale = DEFAULT_LOCALE): TFunction {
  const rules = new Intl.PluralRules(intlTag[locale]);
  return (key, params) => {
    let node: unknown = messages;
    for (const part of key.split(".")) node = (node as Record<string, unknown> | undefined)?.[part];
    if (node && typeof node === "object" && "other" in node) {
      const forms = node as Record<string, string>;
      const n = Number(params?.count ?? 0);
      node = forms[rules.select(n)] ?? forms.other;
    }
    let out = typeof node === "string" ? node : key;
    if (params) {
      for (const [k, v] of Object.entries(params)) out = out.replaceAll(`{${k}}`, String(v));
    }
    return out;
  };
}
