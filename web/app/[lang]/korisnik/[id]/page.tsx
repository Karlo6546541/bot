import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { MrezaOglasa } from '@/components/Kartice';
import { Paginacija } from '@/components/Paginacija';
import { Traka } from '@/components/Traka';
import { PO_STRANICI } from '@/lib/config';
import { jezik, prevedi, prevodilac, put } from '@/lib/i18n';
import { nazivDrzave } from '@/lib/lokacije';
import { dohvatiProfil, traziOglase } from '@/lib/oglasi';
import { brojStranice } from '@/lib/pretraga';
import { javniKlijent } from '@/lib/supabase';
import { datum } from '@/lib/tekst';

export const revalidate = 120;
type P = Promise<{ lang: string; id: string }>;
type SP = Promise<Record<string, string | string[] | undefined>>;

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const { id, lang } = await params;
  const j = jezik(lang);
  const p = await dohvatiProfil(javniKlijent(), id);
  const osnova = `/korisnik/${id}`;
  return p
    ? { title: prevedi(j, '{ime}: oglasi', { ime: p.ime }), alternates: { canonical: put(j, osnova), languages: { hr: osnova, en: put('en', osnova), 'x-default': osnova } } }
    : { title: prevedi(j, 'Korisnik nije pronađen'), robots: { index: false } };
}

export default async function KorisnikStranica({ params, searchParams }: { params: P; searchParams: SP }) {
  const { id, lang } = await params;
  const j = jezik(lang);
  const t = prevodilac(j);
  const sb = javniKlijent();
  const profil = await dohvatiProfil(sb, id);
  if (!profil) notFound();
  const stranica = brojStranice(await searchParams);
  const oglasi = await traziOglase(sb, { korisnik: id }, stranica);
  return (
    <>
      <Traka naslov={profil.ime} natrag="/" />
      <p className="pomoc" style={{ padding: '0 16px' }}>
        {t('Član od {d}', { d: datum(profil.registriran, j) })}
        {profil.grad ? ` · ${profil.grad}, ${nazivDrzave(profil.drzava, j)}` : ''} · {t(oglasi.ukupno === 1 ? '{n} aktivan oglas' : '{n} aktivnih oglasa', { n: oglasi.ukupno })}
      </p>
      {oglasi.stavke.length === 0 ? <div className="prazno"><b>{t('Nema aktivnih oglasa.')}</b></div> : <MrezaOglasa oglasi={oglasi.stavke} jezik={j} />}
      <Paginacija stranica={stranica} ukupnoStranica={Math.max(1, Math.ceil(oglasi.ukupno / PO_STRANICI))} adresa={(s) => `${put(j, `/korisnik/${id}`)}?stranica=${s}`} jezik={j} />
    </>
  );
}
