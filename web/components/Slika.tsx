import Image from 'next/image';

// Vanjske slike koje Vercel smije smanjiti i pretvoriti u WebP/AVIF (puno manje podataka na mobitelu).
const SUPABASE = process.env.NEXT_PUBLIC_SUPABASE_URL ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).host : '';
export const OPTIMIZIRANI_HOSTOVI = ['upload.wikimedia.org', 'thumb.wikimedia.org', 'live.staticflickr.com', 'farm1.staticflickr.com', 'farm2.staticflickr.com', 'farm4.staticflickr.com', 'farm8.staticflickr.com', 'farm9.staticflickr.com', SUPABASE].filter(Boolean);

function optimizira(src: string) {
  try {
    const u = new URL(src);
    return u.protocol === 'https:' && OPTIMIZIRANI_HOSTOVI.includes(u.host);
  } catch {
    return false;
  }
}

/** Slika koja ispunjava roditelja (object-fit iz CSS-a). Nepoznati izvori idu kao obični <img>. */
export function Slika({ src, alt, sizes, prioritet = false, className }: { src: string; alt: string; sizes: string; prioritet?: boolean; className?: string }) {
  if (!src) return null;
  if (!optimizira(src)) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img className={className} src={src} alt={alt} loading={prioritet ? 'eager' : 'lazy'} decoding="async" />;
  }
  return <Image className={className} src={src} alt={alt} fill sizes={sizes} priority={prioritet} quality={70} />;
}
