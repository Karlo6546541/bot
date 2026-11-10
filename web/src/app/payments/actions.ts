"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { getViewer } from "@/lib/auth/session";
import { getMockProvider, getPaymentProvider, getPaymentService } from "@/lib/payments";
import { PaymentError } from "@/lib/payments/types";
import { env } from "@/lib/env";
import type { MessageKey } from "@/lib/i18n";

export type UnlockState = { error?: MessageKey } | undefined;

async function viewerOrLogin(next: string) {
  const viewer = await getViewer();
  if (!viewer) redirect(`/login?next=${encodeURIComponent(next)}`);
  return viewer;
}

export async function unlockChapterAction(_prev: UnlockState, formData: FormData): Promise<UnlockState> {
  const chapterId = z.string().uuid().safeParse(formData.get("chapterId"));
  if (!chapterId.success) return { error: "errors.invalidInput" };
  const viewer = await viewerOrLogin(`/read/${chapterId.data}`);
  const res = await getPaymentService().service.unlockChapter(viewer.id, chapterId.data);
  switch (res.status) {
    case "insufficient_coins":
      return { error: "reader.insufficientCoins" };
    case "not_available":
      return { error: "reader.notAvailable" };
    default:
      revalidatePath(`/read/${chapterId.data}`);
      revalidatePath("/", "layout");
      redirect(`/read/${chapterId.data}`);
  }
}

const planCode = z.string().regex(/^[a-z0-9_]{1,40}$/);

async function startCheckout(kind: "subscription" | "coins", formData: FormData) {
  const code = planCode.safeParse(formData.get("planCode"));
  if (!code.success) redirect("/pricing?error=plan");
  const viewer = await viewerOrLogin("/pricing");
  const provider = await getPaymentProvider();
  const req = {
    userId: viewer.id,
    email: viewer.email,
    planCode: code.data,
    successUrl: `${env.siteUrl}/checkout/success?kind=${kind}`,
    cancelUrl: `${env.siteUrl}/checkout/canceled`,
  };
  let url: string;
  try {
    url = (kind === "subscription" ? await provider.createSubscriptionCheckout(req) : await provider.createCoinCheckout(req)).url;
  } catch (e) {
    if (e instanceof PaymentError) redirect(`/pricing?error=${e.code}`);
    throw e;
  }
  redirect(url);
}

export async function startSubscriptionCheckout(formData: FormData) {
  await startCheckout("subscription", formData);
}

export async function startCoinCheckout(formData: FormData) {
  await startCheckout("coins", formData);
}

export async function openBillingPortalAction() {
  const viewer = await viewerOrLogin("/account");
  const provider = await getPaymentProvider();
  let url: string;
  try {
    url = (await provider.openBillingPortal({ userId: viewer.id, returnUrl: `${env.siteUrl}/account` })).url;
  } catch (e) {
    if (e instanceof PaymentError) redirect(`/account?error=${e.code}`);
    throw e;
  }
  redirect(url);
}

export async function cancelSubscriptionAction() {
  const viewer = await viewerOrLogin("/account");
  const provider = await getPaymentProvider();
  try {
    await provider.cancelSubscription({ userId: viewer.id });
  } catch (e) {
    if (e instanceof PaymentError) redirect(`/account?error=${e.code}`);
    throw e;
  }
  revalidatePath("/account");
  redirect("/account#subscription");
}

// ------------------------------------------------------------------ mock only
export async function completeMockCheckout(formData: FormData) {
  const mock = await getMockProvider();
  if (!mock) redirect("/");
  const viewer = await viewerOrLogin("/pricing");
  const session = String(formData.get("session") ?? "");
  const outcome = formData.get("outcome") === "success" ? "success" : "failure";
  try {
    await mock.completeCheckout(session, outcome, viewer.id);
  } catch (e) {
    if (e instanceof PaymentError) redirect(`/checkout/failed?reason=${e.code}`);
    throw e;
  }
  revalidatePath("/", "layout");
  const { decodeSession } = await import("@/lib/payments/mock/provider");
  const s = decodeSession(session);
  redirect(outcome === "success" ? s.successUrl : "/checkout/failed");
}

export async function simulateSubscriptionEvent(formData: FormData) {
  const mock = await getMockProvider();
  if (!mock) redirect("/");
  const viewer = await viewerOrLogin("/account");
  try {
    if (formData.get("event") === "renew") await mock.simulateRenew(viewer.id);
    else await mock.simulateExpire(viewer.id);
  } catch (e) {
    if (e instanceof PaymentError) redirect(`/account?error=${e.code}`);
    throw e;
  }
  revalidatePath("/", "layout");
  redirect("/account#subscription");
}
