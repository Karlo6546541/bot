import { revalidatePath } from 'next/cache';
import { NextResponse, after, type NextRequest } from 'next/server';
import { javiIndexNow } from '@/lib/indexnow';
import { JEZICI, put } from '@/lib/i18n';
import { podkategorija } from '@/lib/kategorije';
import { dohvatiOglas } from '@/lib/oglasi';
import { putOglasa } from '@/lib/seo';
import { klijentServera } from '@/lib/supabase';

// Nakon objave, izmjene, prodaje ili brisanja oglasa: keširane stranice se odmah
// osvježavaju, pa novi oglas svi vide odmah (ne tek za nekoliko minuta).
export async function POST(request: NextRequest) {
  const sb = await klijentServera();
  const { data } = await sb.auth.getUser();
  if (!data.user) return NextResponse.json({ ok: false }, { status: 401 });
  const { oglasId } = (await request.json().catch(() => ({}))) as { oglasId?: string };
  const o = oglasId ? await dohvatiOglas(sb, oglasId) : null;
  const kat = podkategorija(o?.kategorija);
  for (const j of JEZICI) {
    revalidatePath(`/${j}`);
    revalidatePath(`/${j}/kategorije`);
    if (kat) revalidatePath(`/${j}/kategorije/${kat.sekcija}`);
    if (o) revalidatePath(`/${j}${putOglasa(o)}`);
  }
  if (o) revalidatePath(`/[lang]/korisnik/${o.korisnik_id}`, 'page');
  revalidatePath('/sitemap.xml');
  // Tražilice (Bing i dr.) odmah saznaju za novi ili promijenjeni oglas.
  if (o && o.status !== 'uklonjen') after(() => javiIndexNow(JEZICI.map((j) => put(j, putOglasa(o)))));
  return NextResponse.json({ ok: true });
}
