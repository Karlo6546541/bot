// Ime, slogan i osnovne postavke. Mijenjaju se ovdje ili kroz varijable okruženja.
export const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME || 'Subhasto';
export const APP_SLOGAN = process.env.NEXT_PUBLIC_APP_SLOGAN || 'Oglasnik za kolekcionare';
export const KONTAKT_EMAIL = process.env.NEXT_PUBLIC_CONTACT_EMAIL || 'kontakt@primjer.hr';
/** Javna adresa stranice (za canonical, sitemap i OAuth povratak). */
export const SITE_URL = (
  process.env.NEXT_PUBLIC_SITE_URL ||
  (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : 'http://localhost:3000')
).replace(/\/$/, '');
export const ISTEK_DANA = 30;
export const MAX_SLIKA = 8;
export const PO_STRANICI = 24;
export const SLIKA_PX = 1600;
export const SLIKA_MALA_PX = 480;
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
export const SUPABASE_KEY = process.env.NEXT_PUBLIC_SUPABASE_KEY || '';
export const imaBazu = () => !!SUPABASE_URL && !!SUPABASE_KEY;
