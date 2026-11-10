import "server-only";
import { cookies } from "next/headers";
import { createT, DEFAULT_LOCALE, dictionaries, isLocale, type Locale } from ".";

export async function getLocale(): Promise<Locale> {
  const c = (await cookies()).get("locale")?.value;
  return isLocale(c) ? c : DEFAULT_LOCALE;
}

export async function getI18n() {
  const locale = await getLocale();
  const messages = dictionaries[locale];
  return { locale, messages, t: createT(messages, locale) };
}
