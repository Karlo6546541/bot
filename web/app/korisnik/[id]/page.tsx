import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { MrezaOglasa } from '@/components/Kartice';
import { Paginacija } from '@/components/Paginacija';
import { PO_STRANICI } from '@/lib/config';
import { nazivDrzave } from '@/lib/lokacije';
import { dohvatiProfil, traziOglase } from '@/lib/oglasi';
import { brojStranice } from '@/lib/pretraga';
import { javniKlijent } from '@/lib/supabase';
import { datum } from '@/lib/tekst';

export const revalidate = 120;
type P = Promise<{ id: string }>;
type SP = Promise<Record<string, string | string[] | undefined>>;

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const { id } = await params;
  const p = await dohvatiProfil(javniKlijent(), id);
  return p ? { title: `${p.ime}: oglasi`, alternates: { canonical: `/korisnik/${id}` } } : { title: 'Korisnik nije pronađen', robots: { index: false } };
}

export default async function KorisnikStranica({ params, searchParams }: { params: P; searchParams: SP }) {
  const { id } = await params;
  const sb = javniKlijent();
  const profil = await dohvatiProfil(sb, id);
  if (!profil) notFound();
  const stranica = brojStranice(await searchParams);
  const oglasi = await traziOglase(sb, { korisnik: id }, stranica);
  return (
    <>
      <h1>{profil.ime}</h1>
      <p className="pomoc">
        Član od {datum(profil.registriran)}
        {profil.grad ? ` · ${profil.grad}, ${nazivDrzave(profil.drzava)}` : ''} · {oglasi.ukupno} aktivnih oglasa
      </p>
      {oglasi.stavke.length === 0 ? <div className="prazno ploca">Nema aktivnih oglasa.</div> : <MrezaOglasa oglasi={oglasi.stavke} />}
      <Paginacija stranica={stranica} ukupnoStranica={Math.max(1, Math.ceil(oglasi.ukupno / PO_STRANICI))} adresa={(s) => `/korisnik/${id}?stranica=${s}`} />
    </>
  );
}
