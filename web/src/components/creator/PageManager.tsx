"use client";
import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useI18n } from "@/lib/i18n/client";
import { createBrowserSupabase } from "@/lib/supabase/browser";
import { extFor, naturalCompare, prepareImage } from "@/lib/images/prepare";
import { saveChapterPages } from "@/app/creator/actions";

export interface ManagedPage {
  key: string;
  storagePath: string;
  width: number;
  height: number;
  previewUrl: string;
}

export function PageManager({
  seriesId,
  chapterId,
  initialPages,
}: {
  seriesId: string;
  chapterId: string;
  initialPages: ManagedPage[];
}) {
  const { t } = useI18n();
  const router = useRouter();
  const [pages, setPages] = useState(initialPages);
  const [dirty, setDirty] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [saving, startSave] = useTransition();
  const dragIndex = useRef<number | null>(null);
  const [dragOver, setDragOver] = useState(false);

  const update = (next: ManagedPage[]) => {
    setPages(next);
    setDirty(true);
    setMessage(null);
  };

  const move = (from: number, to: number) => {
    if (to < 0 || to >= pages.length || from === to) return;
    const next = [...pages];
    const [item] = next.splice(from, 1);
    next.splice(to, 0, item);
    update(next);
  };

  async function upload(files: File[]) {
    const images = files.filter((f) => f.type.startsWith("image/")).sort((a, b) => naturalCompare(a.name, b.name));
    if (!images.length) return;
    const supabase = createBrowserSupabase();
    const added: ManagedPage[] = [];
    setProgress({ done: 0, total: images.length });
    try {
      for (const [i, file] of images.entries()) {
        const img = await prepareImage(file, 1200);
        const path = `${seriesId}/${chapterId}/${crypto.randomUUID()}.${extFor(img.blob)}`;
        const { error } = await supabase.storage
          .from("pages")
          .upload(path, img.blob, { contentType: img.blob.type, cacheControl: "31536000" });
        if (error) throw error;
        added.push({ key: path, storagePath: path, width: img.width, height: img.height, previewUrl: URL.createObjectURL(img.blob) });
        setProgress({ done: i + 1, total: images.length });
      }
    } catch {
      setMessage({ ok: false, text: t("errors.uploadFailed") });
    } finally {
      setProgress(null);
      if (added.length) update([...pages, ...added]);
    }
  }

  const save = () =>
    startSave(async () => {
      const res = await saveChapterPages(
        chapterId,
        pages.map((p) => ({ storage_path: p.storagePath, width: p.width, height: p.height })),
      );
      setMessage({ ok: res.ok, text: res.ok ? t("common.saved") : t("common.error") });
      if (res.ok) {
        setDirty(false);
        router.refresh();
      }
    });

  return (
    <section aria-labelledby="pages-title" className="space-y-3">
      <h2 id="pages-title" className="h2">
        {t("creator.pages")} <span className="muted text-base font-normal">({pages.length})</span>
      </h2>

      <label
        onDragOver={(e) => {
          if (e.dataTransfer.types.includes("Files")) {
            e.preventDefault();
            setDragOver(true);
          }
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          if (!e.dataTransfer.files.length) return;
          e.preventDefault();
          setDragOver(false);
          void upload([...e.dataTransfer.files]);
        }}
        className={`flex min-h-28 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-4 text-center ${dragOver ? "border-brand-500 bg-brand-50 dark:bg-ink-800" : "border-ink-200 dark:border-ink-700"}`}
      >
        <span className="font-semibold">{t("creator.dropHere")}</span>
        <span className="muted text-xs">{t("creator.uploadHelp")}</span>
        <input
          type="file"
          accept="image/*"
          multiple
          className="sr-only"
          disabled={!!progress}
          onChange={(e) => {
            void upload([...(e.target.files ?? [])]);
            e.target.value = "";
          }}
        />
      </label>
      {progress && (
        <p role="status" aria-live="polite" className="text-sm">
          {t("creator.uploading", { done: progress.done, total: progress.total })}
        </p>
      )}

      <p className="muted text-xs">{t("creator.reorderHelp")}</p>
      <ol className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
        {pages.map((p, i) => (
          <li
            key={p.key}
            draggable
            onDragStart={() => (dragIndex.current = i)}
            onDragOver={(e) => e.preventDefault()}
            onDrop={(e) => {
              e.preventDefault();
              if (dragIndex.current !== null) move(dragIndex.current, i);
              dragIndex.current = null;
            }}
            className="card cursor-grab p-2 active:cursor-grabbing"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.previewUrl} alt={`${t("creator.pages")} ${i + 1}`} loading="lazy" className="aspect-[2/3] w-full rounded object-cover object-top" />
            <div className="mt-2 flex items-center justify-between gap-1">
              <span className="text-sm font-bold">{i + 1}</span>
              <span className="flex gap-1">
                <button type="button" className="btn-ghost min-h-9 px-2" onClick={() => move(i, i - 1)} disabled={i === 0} aria-label={`${t("creator.moveUp")} (${i + 1})`}>↑</button>
                <button type="button" className="btn-ghost min-h-9 px-2" onClick={() => move(i, i + 1)} disabled={i === pages.length - 1} aria-label={`${t("creator.moveDown")} (${i + 1})`}>↓</button>
                <button type="button" className="btn-ghost min-h-9 px-2 text-red-700" onClick={() => update(pages.filter((_, j) => j !== i))} aria-label={`${t("creator.removePage")} (${i + 1})`}>✕</button>
              </span>
            </div>
          </li>
        ))}
      </ol>

      <div className="flex items-center gap-3">
        <button type="button" className="btn-primary" onClick={save} disabled={!dirty || saving || !!progress}>
          {saving ? t("common.loading") : t("creator.saveOrder")}
        </button>
        {message && (
          <p role={message.ok ? "status" : "alert"} className={message.ok ? "text-emerald-700" : "text-red-700"}>
            {message.text}
          </p>
        )}
      </div>
    </section>
  );
}
