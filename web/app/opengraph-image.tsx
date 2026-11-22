import { ImageResponse } from 'next/og';
import { APP_NAME, APP_SLOGAN } from '@/lib/config';

export const alt = `${APP_NAME} – ${APP_SLOGAN}`;
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function Slika() {
  return new ImageResponse(
    (
      <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 80, background: '#171c1d', color: '#f2f4f4' }}>
        <div style={{ fontSize: 120, fontWeight: 800, color: '#449da8', letterSpacing: -4 }}>{APP_NAME}</div>
        <div style={{ fontSize: 56, marginTop: 16 }}>{APP_SLOGAN}</div>
        <div style={{ fontSize: 34, marginTop: 40, color: '#a4adaf' }}>Kartice · Kovanice · Marke · Stripovi · Figure · Ploče</div>
      </div>
    ),
    size,
  );
}
