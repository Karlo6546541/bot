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
      <div className="cover">
        {src && (
          <Image
            src={src}
            alt=""
            fill
            sizes="(min-width: 1024px) 200px, (min-width: 640px) 25vw, 45vw"
            className="object-cover"
            priority={priority}
          />
        )}
        {series.genres[0] && (
          <span className="badge-early absolute left-1.5 top-1.5">{t(`genres.${series.genres[0]}` as MessageKey)}</span>
        )}
      </div>
      <h3 className="mt-3 line-clamp-2 text-sm font-black uppercase leading-tight tracking-tight">{series.title}</h3>
      <p className="muted line-clamp-1 text-xs font-semibold">{series.creators?.pen_name}</p>
    </Link>
  );
}

export function SeriesGrid({ children }: { children: React.ReactNode }) {
  return <div className="grid grid-cols-2 gap-x-4 gap-y-7 sm:grid-cols-4 lg:grid-cols-5">{children}</div>;
}
