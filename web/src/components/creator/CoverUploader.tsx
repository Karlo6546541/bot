"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useI18n } from "@/lib/i18n/client";
import { createBrowserSupabase } from "@/lib/supabase/browser";
import { extFor, prepareImage } from "@/lib/images/prepare";
import { setSeriesCover } from "@/app/creator/actions";

export function CoverUploader({ seriesId, currentUrl }: { seriesId: string; currentUrl: string | null }) {
  const { t } = useI18n();
  const router = useRouter();
  const [preview, setPreview] = useState(currentUrl);
  const [error, setError] = useState(false);
  const [pending, start] = useTransition();

  const onFile = (file: File | undefined) => {
    if (!file) return;
    setError(false);
    start(async () => {
      try {
        const img = await prepareImage(file, 600);
        const path = `${seriesId}/cover-${Date.now()}.${extFor(img.blob)}`;
        const { error: upErr } = await createBrowserSupabase()
          .storage.from("covers")
          .upload(path, img.blob, { contentType: img.blob.type, cacheControl: "31536000" });
        if (upErr) throw upErr;
        await setSeriesCover(seriesId, path);
        setPreview(URL.createObjectURL(img.blob));
        router.refresh();
      } catch {
        setError(true);
      }
    });
  };

  return (
    <div className="flex items-end gap-4">
      <div className="aspect-[2/3] w-28 overflow-hidden rounded-lg bg-ink-200 dark:bg-ink-800">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {preview && <img src={preview} alt="" className="h-full w-full object-cover" />}
      </div>
      <div>
        <label className="btn-secondary cursor-pointer">
          {pending ? t("common.loading") : t("creator.cover")}
          <input type="file" accept="image/*" className="sr-only" onChange={(e) => onFile(e.target.files?.[0])} disabled={pending} />
        </label>
        <p className="muted mt-1 text-xs">{t("creator.coverHelp")}</p>
        {error && <p role="alert" className="text-sm text-red-700">{t("errors.uploadFailed")}</p>}
      </div>
    </div>
  );
}
