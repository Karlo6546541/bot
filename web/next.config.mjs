/** @type {import('next').NextConfig} */
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL) : null;
const razvoj = process.env.NODE_ENV !== 'production';
// Content-Security-Policy: skripte, okviri i veze samo s naše domene, Supabasea i Google prijave.
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${razvoj ? " 'unsafe-eval'" : ''} https://accounts.google.com/gsi/client`,
  "style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  `connect-src 'self'${supabaseUrl ? ` ${supabaseUrl.origin} ${supabaseUrl.protocol === 'https:' ? 'wss' : 'ws'}://${supabaseUrl.host}` : ''} https://accounts.google.com/gsi/`,
  'frame-src https://accounts.google.com/gsi/',
  "frame-ancestors 'self'",
  "base-uri 'self'",
  "form-action 'self' https://accounts.google.com",
  "object-src 'none'",
  "manifest-src 'self'",
  "worker-src 'self' blob:",
  ...(supabaseUrl?.protocol === 'https:' ? ['upgrade-insecure-requests'] : []),
].join('; ');
const supabaseHost = process.env.NEXT_PUBLIC_SUPABASE_URL ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).host : undefined;
const hostovi = ['upload.wikimedia.org', 'thumb.wikimedia.org', 'live.staticflickr.com', 'farm1.staticflickr.com', 'farm2.staticflickr.com', 'farm4.staticflickr.com', 'farm8.staticflickr.com', 'farm9.staticflickr.com', supabaseHost].filter(Boolean);
export default {
  poweredByHeader: false,
  compress: true,
  images: {
    remotePatterns: hostovi.map((hostname) => ({ protocol: 'https', hostname })),
    formats: ['image/avif', 'image/webp'],
    deviceSizes: [360, 480, 640, 828, 1080, 1280],
    imageSizes: [96, 160, 240, 320],
    minimumCacheTTL: 2678400,
  },
  experimental: { optimizePackageImports: ['@supabase/supabase-js'] },
  async headers() {
    return [
      { source: '/(.*)', headers: [
        { key: 'X-Content-Type-Options', value: 'nosniff' },
        { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
        { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
        { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
        { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=(), browsing-topics=()' },
        // Google prijava otvara skočni prozor koji mora moći javiti rezultat stranici.
        { key: 'Cross-Origin-Opener-Policy', value: 'same-origin-allow-popups' },
        { key: 'X-DNS-Prefetch-Control', value: 'on' },
        { key: 'Content-Security-Policy', value: csp },
      ] },
      { source: '/fonts/(.*)', headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }] },
    ];
  },
};
