import { NextResponse, type NextRequest } from 'next/server';
import { osigurajProfil, sigurnoNatrag } from '@/lib/korisnik';
import { klijentServera } from '@/lib/supabase';

// Povratak s Google prijave i s poveznice za potvrdu e-maila.
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const natrag = sigurnoNatrag(searchParams.get('natrag'));
  const code = searchParams.get('code');
  if (code) {
    const sb = await klijentServera();
    const { error } = await sb.auth.exchangeCodeForSession(code);
    if (error) return NextResponse.redirect(`${origin}/prijava?greska=${encodeURIComponent(error.message)}`);
    const { data } = await sb.auth.getUser();
    if (data.user) await osigurajProfil(sb, data.user);
  }
  return NextResponse.redirect(`${origin}${natrag}`);
}
