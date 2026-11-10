import type { Metadata, Viewport } from "next";
import "./globals.css";
import { getI18n } from "@/lib/i18n/server";
import { I18nProvider } from "@/lib/i18n/client";
import { SiteHeader } from "@/components/layout/SiteHeader";
import { BottomNav } from "@/components/layout/BottomNav";
import { ServiceWorker } from "@/components/layout/ServiceWorker";
import { getViewer } from "@/lib/auth/session";
import { env } from "@/lib/env";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return {
    title: { default: t("common.appName"), template: `%s · ${t("common.appName")}` },
    description: t("common.tagline"),
    applicationName: t("common.appName"),
    appleWebApp: { capable: true, title: t("common.appName"), statusBarStyle: "black-translucent" },
    icons: { icon: "/icons/icon-192.png", apple: "/icons/apple-touch-icon.png" },
  };
}

export const viewport: Viewport = {
  themeColor: "#16161a",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const { locale, messages, t } = await getI18n();
  const viewer = await getViewer();
  return (
    <html lang={locale}>
      <body className="min-h-dvh">
        <I18nProvider locale={locale} messages={messages}>
          <a
            href="#main"
            className="sr-only focus:not-sr-only focus:fixed focus:left-2 focus:top-2 focus:z-50 focus:rounded focus:bg-white focus:px-3 focus:py-2 focus:text-ink-900"
          >
            {t("common.skipToContent")}
          </a>
          {env.paymentProvider === "mock" && (
            <div role="note" className="bg-amber-200 px-3 py-1 text-center text-xs font-medium text-amber-950">
              {t("common.testModeBanner")}
            </div>
          )}
          <SiteHeader viewer={viewer} />
          <main id="main" className="mx-auto w-full max-w-5xl px-4 pb-24 pt-4 sm:pb-12">
            {children}
          </main>
          <BottomNav loggedIn={!!viewer} role={viewer?.profile.role ?? null} />
          <ServiceWorker />
        </I18nProvider>
      </body>
    </html>
  );
}
