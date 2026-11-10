import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile, UserRole } from "@/lib/supabase/types";

export interface Viewer {
  id: string;
  email: string;
  profile: Profile;
}

/** Current signed-in user (validated with the auth server), cached per request. */
export const getViewer = cache(async (): Promise<Viewer | null> => {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  const { data: profile } = await supabase.from("profiles").select("*").eq("id", data.user.id).single();
  if (!profile) return null;
  return { id: data.user.id, email: data.user.email ?? "", profile };
});

export async function requireViewer(next?: string): Promise<Viewer> {
  const viewer = await getViewer();
  if (!viewer) redirect(`/login${next ? `?next=${encodeURIComponent(next)}` : ""}`);
  return viewer;
}

export async function requireRole(role: UserRole, next?: string): Promise<Viewer> {
  const viewer = await requireViewer(next);
  const ok = viewer.profile.role === role || viewer.profile.role === "admin";
  if (!ok) redirect("/forbidden");
  return viewer;
}

export async function requireAdmin(): Promise<Viewer> {
  const viewer = await requireViewer("/admin");
  if (viewer.profile.role !== "admin") redirect("/forbidden");
  return viewer;
}

/** For server actions / route handlers: throws instead of redirecting. */
export class AuthError extends Error {
  constructor(public readonly code: "unauthenticated" | "forbidden") {
    super(code);
  }
}

export async function assertViewer(): Promise<Viewer> {
  const viewer = await getViewer();
  if (!viewer) throw new AuthError("unauthenticated");
  return viewer;
}

export async function assertAdmin(): Promise<Viewer> {
  const viewer = await assertViewer();
  if (viewer.profile.role !== "admin") throw new AuthError("forbidden");
  return viewer;
}
