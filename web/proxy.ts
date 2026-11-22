import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { SUPABASE_KEY, SUPABASE_URL, imaBazu } from '@/lib/config';

// Jezik po adresi: /en/... je engleski, sve ostalo hrvatski (interno /hr/...).
// Privatne stranice traže prijavu; samo za njih se poziva baza (javne stranice ostaju brze i keširane).
const PRIVATNO = /^\/(objavi|moji-oglasi|poruke|favoriti|profil|admin)(\/|$)|^\/oglas\/[^/]+\/uredi$/;

export async function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  // /hr/... nije javna adresa: vodi na kanonsku bez prefiksa.
  if (pathname === '/hr' || pathname.startsWith('/hr/')) {
    const url = request.nextUrl.clone();
    url.pathname = pathname.slice(3) || '/';
    return NextResponse.redirect(url, 308);
  }
  const en = pathname === '/en' || pathname.startsWith('/en/');
  const ostatak = en ? pathname.slice(3) || '/' : pathname;
  const odgovor = () => {
    if (en) return NextResponse.next({ request });
    const url = request.nextUrl.clone();
    url.pathname = `/hr${pathname === '/' ? '' : pathname}`;
    return NextResponse.rewrite(url, { request });
  };
  let response = odgovor();
  if (!PRIVATNO.test(ostatak) || !imaBazu()) return response;

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list) => {
        list.forEach(({ name, value }) => request.cookies.set(name, value));
        response = odgovor();
        list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data } = await supabase.auth.getUser();
  if (!data.user) {
    const url = request.nextUrl.clone();
    url.pathname = en ? '/en/prijava' : '/prijava';
    url.search = `?natrag=${encodeURIComponent(pathname + search)}`;
    return NextResponse.redirect(url);
  }
  return response;
}

export const config = {
  // Sve osim Next datoteka, auth povratka, fontova i metapodataka (robots, sitemap, ikone).
  matcher: ['/((?!_next/|auth/|fonts/|api/|favicon|icon|opengraph-image|robots.txt|sitemap.xml|manifest.webmanifest).*)'],
};
