"use client";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { useI18n } from "@/lib/i18n/client";

export interface ReaderPage {
  id: string;
  url: string;
  width: number;
  height: number;
}

type Mode = "vertical" | "paged";
type Progress = { pageIndex: number; scrollRatio: number };

interface Props {
  chapterId: string;
  seriesSlug: string;
  seriesTitle: string;
  chapterNumber: number;
  chapterTitle: string;
  initialPages: ReaderPage[];
  initialExpiresAt: number;
  initialProgress: Progress | null;
  prevChapterId: string | null;
  nextChapterId: string | null;
  loggedIn: boolean;
  emptyText: string;
}

const MODE_KEY = "kadar.readerMode";
const progressKey = (id: string) => `kadar.progress.${id}`;

function readLocal(chapterId: string): Progress | null {
  try {
    const raw = localStorage.getItem(progressKey(chapterId));
    return raw ? (JSON.parse(raw) as Progress) : null;
  } catch {
    return null;
  }
}

export function Reader(props: Props) {
  const { t } = useI18n();
  const { chapterId, initialPages } = props;
  const [mode, setMode] = useState<Mode>("vertical");
  const [pages, setPages] = useState(initialPages);
  const [current, setCurrent] = useState(0);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState<Record<string, boolean>>({});
  const loaded = useRef(new Set<string>());
  const retried = useRef(new Set<string>());
  const refreshing = useRef<Promise<void> | null>(null);
  const pageRefs = useRef<(HTMLDivElement | null)[]>([]);
  const lastSaved = useRef<string>("");
  const total = pages.length;
  const isEnd = mode === "paged" && current >= total; // "end of chapter" pseudo-page

  // ---- mount: mode preference + restore position (server progress wins over local) ----
  useEffect(() => {
    try {
      const m = localStorage.getItem(MODE_KEY);
      if (m === "paged" || m === "vertical") setMode(m);
    } catch {}
    const p = props.initialProgress ?? readLocal(chapterId);
    if (p) setCurrent(Math.min(Math.max(0, p.pageIndex), Math.max(0, total - 1)));
    setReady(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!ready || mode !== "vertical" || current === 0) return;
    pageRefs.current[current]?.scrollIntoView({ block: "start" });
    // only on first render after restore / mode switch
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, mode]);

  const changeMode = (m: Mode) => {
    setMode(m);
    try {
      localStorage.setItem(MODE_KEY, m);
    } catch {}
  };

  // ---- signed URL refresh: only replaces URLs of pages not yet loaded ----
  const refreshUrls = useCallback(() => {
    refreshing.current ??= fetch(`/api/chapters/${chapterId}/pages`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((d: { pages: ReaderPage[] } | null) => {
        if (!d) return;
        const fresh = new Map(d.pages.map((p) => [p.id, p]));
        setPages((prev) => prev.map((p) => (loaded.current.has(p.id) ? p : (fresh.get(p.id) ?? p))));
      })
      .finally(() => {
        refreshing.current = null;
      });
    return refreshing.current;
  }, [chapterId]);

  const onImgError = useCallback(
    (id: string) => {
      if (retried.current.has(id)) {
        setFailed((f) => ({ ...f, [id]: true }));
        return;
      }
      retried.current.add(id);
      void refreshUrls();
    },
    [refreshUrls],
  );

  const retryPage = (id: string) => {
    retried.current.delete(id);
    setFailed((f) => ({ ...f, [id]: false }));
    void refreshUrls();
  };

  // ---- vertical mode: track current page from scroll position ----
  useEffect(() => {
    if (mode !== "vertical") return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const mid = window.innerHeight * 0.4;
        let idx = 0;
        pageRefs.current.forEach((el, i) => {
          if (el && el.getBoundingClientRect().top <= mid) idx = i;
        });
        setCurrent(idx);
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      cancelAnimationFrame(frame);
    };
  }, [mode]);

  // ---- paged mode: preload the next two pages ----
  useEffect(() => {
    if (mode !== "paged") return;
    for (const p of pages.slice(current + 1, current + 3)) {
      const img = new Image();
      img.decoding = "async";
      img.src = p.url;
    }
  }, [mode, current, pages]);

  const go = useCallback(
    (delta: number) => {
      setCurrent((c) => Math.min(Math.max(0, c + delta), total)); // `total` = end screen
      window.scrollTo({ top: 0 });
    },
    [total],
  );

  useEffect(() => {
    if (mode !== "paged") return;
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLElement && ["INPUT", "SELECT", "TEXTAREA"].includes(e.target.tagName)) return;
      if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") {
        e.preventDefault();
        go(1);
      } else if (e.key === "ArrowLeft" || e.key === "PageUp") {
        e.preventDefault();
        go(-1);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mode, go]);

  // swipe (paged mode)
  const touchStart = useRef<number | null>(null);

  // ---- persist progress (debounced; localStorage always, server when logged in) ----
  const buildProgress = useCallback(() => {
    const pageIndex = Math.min(current, Math.max(0, total - 1));
    const scrollRatio = total > 1 ? pageIndex / (total - 1) : 1;
    return { chapterId, pageIndex, scrollRatio, completed: total === 0 || current >= total - 1 };
  }, [chapterId, current, total]);

  useEffect(() => {
    if (!ready) return;
    const p = buildProgress();
    try {
      localStorage.setItem(progressKey(chapterId), JSON.stringify({ pageIndex: p.pageIndex, scrollRatio: p.scrollRatio }));
    } catch {}
    if (!props.loggedIn) return;
    const key = JSON.stringify(p);
    if (key === lastSaved.current) return;
    const timer = setTimeout(() => {
      lastSaved.current = key;
      void fetch("/api/progress", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: key,
        keepalive: true,
      }).catch(() => {});
    }, 1500);
    return () => clearTimeout(timer);
  }, [ready, buildProgress, chapterId, props.loggedIn]);

  useEffect(() => {
    if (!props.loggedIn) return;
    const flush = () => {
      const key = JSON.stringify(buildProgress());
      if (key !== lastSaved.current) {
        lastSaved.current = key;
        navigator.sendBeacon?.("/api/progress", new Blob([key], { type: "application/json" }));
      }
    };
    window.addEventListener("pagehide", flush);
    return () => window.removeEventListener("pagehide", flush);
  }, [buildProgress, props.loggedIn]);

  const alt = (i: number) =>
    t("reader.imageAlt", { series: props.seriesTitle, chapter: props.chapterNumber, n: i + 1 });

  const renderImg = (p: ReaderPage, i: number, eager: boolean) =>
    failed[p.id] ? (
      <div className="flex flex-col items-center justify-center gap-3 bg-ink-900 text-ink-100" style={{ aspectRatio: `${p.width}/${p.height}` }}>
        <p>{t("reader.imageError")}</p>
        <button className="btn-secondary" onClick={() => retryPage(p.id)}>{t("reader.retry")}</button>
      </div>
    ) : (
      // Plain <img>: signed URLs are already sized; next/image would proxy and re-cache locked content.
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={p.url}
        width={p.width}
        height={p.height}
        alt={alt(i)}
        loading={eager ? "eager" : "lazy"}
        decoding="async"
        fetchPriority={i === 0 ? "high" : "auto"}
        draggable={false}
        onLoad={() => loaded.current.add(p.id)}
        onError={() => onImgError(p.id)}
        className="block h-auto w-full bg-ink-800 select-none"
        style={{ aspectRatio: `${p.width}/${p.height}` }}
      />
    );

  const chapterNav = (
    <nav aria-label={t("series.chapters")} className="flex items-center justify-between gap-2 px-4 py-6">
      {props.prevChapterId ? (
        <Link href={`/read/${props.prevChapterId}`} className="btn-secondary">← {t("reader.prevChapter")}</Link>
      ) : (
        <span />
      )}
      {props.nextChapterId ? (
        <Link href={`/read/${props.nextChapterId}`} className="btn-primary">{t("reader.nextChapter")} →</Link>
      ) : (
        <Link href={`/series/${props.seriesSlug}`} className="btn-secondary">{t("reader.backToSeries")}</Link>
      )}
    </nav>
  );

  return (
    <div className="-mx-4 -mt-4 bg-ink-950 text-ink-100">
      <div className="sticky top-14 z-20 flex items-center gap-2 border-b border-ink-800 bg-ink-950/95 px-3 py-2 backdrop-blur">
        <Link href={`/series/${props.seriesSlug}`} className="btn-ghost min-h-10 px-2 text-ink-100" aria-label={t("reader.backToSeries")}>
          ←
        </Link>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{props.seriesTitle}</p>
          <p className="truncate text-xs text-ink-400">
            {t("series.chapterN", { n: props.chapterNumber })}
            {props.chapterTitle ? ` · ${props.chapterTitle}` : ""}
          </p>
        </div>
        <p className="text-xs tabular-nums text-ink-400" aria-live="polite">
          {total > 0 && t("reader.pageOf", { n: Math.min(current + 1, total), total })}
        </p>
        <fieldset className="flex overflow-hidden rounded-lg border border-ink-700">
          <legend className="sr-only">{t("reader.settings")}</legend>
          {(["vertical", "paged"] as const).map((m) => (
            <label key={m} className={`cursor-pointer px-2 py-1.5 text-xs ${mode === m ? "bg-brand-600 text-white" : "text-ink-300"}`}>
              <input type="radio" name="mode" value={m} checked={mode === m} onChange={() => changeMode(m)} className="sr-only" />
              <span aria-hidden>{m === "vertical" ? "↕" : "↔"}</span>
              <span className="sr-only">{t(m === "vertical" ? "reader.modeVertical" : "reader.modePaged")}</span>
            </label>
          ))}
        </fieldset>
      </div>

      {total === 0 ? (
        <p className="px-4 py-16 text-center">{props.emptyText}</p>
      ) : mode === "vertical" ? (
        <div className="mx-auto max-w-[800px]">
          {pages.map((p, i) => (
            <div key={p.id} ref={(el) => { pageRefs.current[i] = el; }}>
              {renderImg(p, i, i < 2)}
            </div>
          ))}
          <p className="pt-8 text-center text-sm text-ink-400">{t("reader.endOfChapter")}</p>
          {chapterNav}
        </div>
      ) : (
        <div className="mx-auto max-w-[800px]">
          <div
            className="relative touch-pan-y"
            onTouchStart={(e) => { touchStart.current = e.touches[0].clientX; }}
            onTouchEnd={(e) => {
              if (touchStart.current === null) return;
              const dx = e.changedTouches[0].clientX - touchStart.current;
              touchStart.current = null;
              if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
            }}
          >
            {isEnd ? (
              <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4">
                <p className="text-lg font-semibold">{t("reader.endOfChapter")}</p>
                {chapterNav}
              </div>
            ) : (
              <>
                {renderImg(pages[current], current, true)}
                {/* Large tap zones; the buttons below are the accessible equivalent. */}
                <button aria-hidden tabIndex={-1} className="absolute inset-y-0 left-0 w-1/3" onClick={() => go(-1)} />
                <button aria-hidden tabIndex={-1} className="absolute inset-y-0 right-0 w-2/3" onClick={() => go(1)} />
              </>
            )}
          </div>
          <div className="flex items-center justify-between gap-2 px-4 py-3">
            <button className="btn-secondary" onClick={() => go(-1)} disabled={current === 0}>
              ← <span className="sr-only sm:not-sr-only">{t("reader.prevPage")}</span>
            </button>
            <span className="text-sm tabular-nums text-ink-400">{Math.min(current + 1, total)} / {total}</span>
            <button className="btn-primary" onClick={() => go(1)} disabled={isEnd}>
              <span className="sr-only sm:not-sr-only">{t("reader.nextPage")}</span> →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
