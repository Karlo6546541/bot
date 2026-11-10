"use client";
import Link from "next/link";
import { useActionState } from "react";
import { useI18n } from "@/lib/i18n/client";
import { login, signup, type FormState } from "./actions";
import { FormMessage } from "@/components/forms/FormMessage";

export function AuthForm({ mode, next }: { mode: "login" | "signup"; next?: string }) {
  const { t } = useI18n();
  const [state, action, pending] = useActionState<FormState, FormData>(mode === "login" ? login : signup, undefined);
  return (
    <div className="mx-auto max-w-sm">
      <h1 className="h1 mb-6">{t(mode === "login" ? "auth.loginTitle" : "auth.signupTitle")}</h1>
      <form action={action} className="space-y-4" noValidate>
        <input type="hidden" name="next" value={next ?? "/"} />
        {mode === "signup" && (
          <div>
            <label className="label" htmlFor="displayName">{t("auth.displayName")}</label>
            <input className="input" id="displayName" name="displayName" required maxLength={60} autoComplete="nickname" />
          </div>
        )}
        <div>
          <label className="label" htmlFor="email">{t("auth.email")}</label>
          <input className="input" id="email" name="email" type="email" required autoComplete="email" inputMode="email" />
        </div>
        <div>
          <label className="label" htmlFor="password">{t("auth.password")}</label>
          <input
            className="input"
            id="password"
            name="password"
            type="password"
            required
            minLength={mode === "signup" ? 8 : undefined}
            autoComplete={mode === "login" ? "current-password" : "new-password"}
          />
        </div>
        <FormMessage error={state?.error} ok={state?.ok} />
        <button className="btn-primary w-full" disabled={pending}>
          {pending ? t("common.loading") : t(mode === "login" ? "auth.loginSubmit" : "auth.signupSubmit")}
        </button>
      </form>
      <p className="muted mt-6 text-sm">
        {mode === "login" ? t("auth.noAccount") : t("auth.haveAccount")}{" "}
        <Link className="font-semibold text-brand-600 underline" href={mode === "login" ? "/signup" : "/login"}>
          {t(mode === "login" ? "nav.signup" : "nav.login")}
        </Link>
      </p>
    </div>
  );
}
