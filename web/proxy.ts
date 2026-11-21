import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { SUPABASE_KEY, SUPABASE_URL, imaBazu } from '@/lib/config';

// Privatne stranice traže prijavu; usput se osvježava sesija u kolačićima.
// Javne stranice ne prolaze ovuda, pa ostaju keširane.
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  if (!imaBazu()) return response;
  const supabase = createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list) => {
        list.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data } = await supabase.auth.getUser();
  if (!data.user) {
    const url = request.nextUrl.clone();
    const natrag = request.nextUrl.pathname + request.nextUrl.search;
    url.pathname = '/prijava';
    url.search = `?natrag=${encodeURIComponent(natrag)}`;
    return NextResponse.redirect(url);
  }
  return response;
}

export const config = {
  matcher: ['/objavi', '/moji-oglasi', '/poruke/:path*', '/favoriti', '/profil', '/admin', '/oglas/:id/uredi'],
};
