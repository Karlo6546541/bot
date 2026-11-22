/** @type {import('next').NextConfig} */
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
      ] },
      { source: '/fonts/(.*)', headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }] },
    ];
  },
};
