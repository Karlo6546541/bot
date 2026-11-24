import type { MetadataRoute } from 'next';
import { APP_NAME, APP_SLOGAN } from '@/lib/config';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: `${APP_NAME} – ${APP_SLOGAN}`,
    short_name: APP_NAME,
    description: 'Oglasnik za kolekcionare: kartice, kovanice, marke, stripovi, figure i ploče.',
    start_url: '/',
    display: 'standalone',
    lang: 'hr',
    background_color: '#171c1d',
    theme_color: '#171c1d',
    icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' }],
  };
}
