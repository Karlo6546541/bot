import { redirect } from "next/navigation";
import { getI18n } from "@/lib/i18n/server";
import { requireViewer } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { ActionForm } from "@/components/creator/ActionForm";
import { applyAsCreator } from "../actions";

export default async function ApplyPage() {
  const viewer = await requireViewer("/creator/apply");
  const { t } = await getI18n();
  const supabase = await createClient();
  const { data: creator } = await supabase.from("creators").select("status").eq("id", viewer.id).maybeSingle();
  if (creator?.status === "approved") redirect("/creator");

  return (
    <div className="mx-auto max-w-lg space-y-4">
      <h1 className="h1">{t("creator.applyTitle")}</h1>
      {creator?.status === "pending" ? (
        <div className="card" role="status">
          <h2 className="h2">{t("creator.pendingTitle")}</h2>
          <p className="muted mt-1">{t("creator.pendingText")}</p>
        </div>
      ) : creator?.status === "rejected" ? (
        <p className="card" role="status">{t("creator.rejectedText")}</p>
      ) : (
        <>
          <p className="muted">{t("creator.applyText")}</p>
          <ActionForm action={applyAsCreator} submitLabel={t("creator.applySubmit")}>
            <div>
              <label className="label" htmlFor="pen_name">{t("creator.penName")}</label>
              <input className="input" id="pen_name" name="pen_name" required minLength={2} maxLength={60} defaultValue={viewer.profile.display_name} />
            </div>
            <div>
              <label className="label" htmlFor="bio">{t("creator.bio")}</label>
              <textarea className="input min-h-24" id="bio" name="bio" maxLength={2000} />
            </div>
            <div>
              <label className="label" htmlFor="portfolio_url">{t("creator.portfolio")}</label>
              <input className="input" id="portfolio_url" name="portfolio_url" type="url" inputMode="url" placeholder="https://" />
            </div>
            <div>
              <label className="label" htmlFor="application_note">{t("creator.note")}</label>
              <textarea className="input min-h-24" id="application_note" name="application_note" maxLength={2000} />
            </div>
          </ActionForm>
        </>
      )}
    </div>
  );
}
