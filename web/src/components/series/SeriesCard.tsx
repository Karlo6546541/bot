import Image from "next/image";
import Link from "next/link";
import { coverUrl } from "@/lib/supabase/storage";
import type { SeriesCardData } from "@/lib/catalog";
import { getI18n } from "@/lib/i18n/server";
import type { MessageKey } from "@/lib/i18n";

export async function SeriesCard({ series, priority = false }: { series: SeriesCardData; priority?: boolean }) {
  const { t } = await getI18n();
  const src = coverUrl(series.cover_path);
  return (
    <Link href={`/series/${series.slug}`} className="group block">
      <div className="relative aspect-[2/3] overflow-hidden rounded-lg bg-ink-200 dark:bg-ink-800">
        {src && (
          <Image
            src={src}
            alt=""
            fill
            sizes="(min-width: 1024px) 200px, (min-width: 640px) 25vw, 45vw"
            className="object-cover transition-transform group-hover:scale-105"
            priority={priority}
          />
        )}
      </div>
      <h3 className="mt-2 line-clamp-2 text-sm font-semibold leading-tight">{series.title}</h3>
      <p className="muted line-clamp-1 text-xs">
        {series.creators?.pen_name}
        {series.genres[0] ? ` · ${t(`genres.${series.genres[0]}` as MessageKey)}` : ""}
      </p>
    </Link>
  );
}

export function SeriesGrid({ children }: { children: React.ReactNode }) {
  return <div className="grid grid-cols-2 gap-x-3 gap-y-5 sm:grid-cols-4 lg:grid-cols-5">{children}</div>;
}
