import type { Metadata } from 'next';
import Link from 'next/link';
import { Traka } from '@/components/Traka';
import { PravnoNapomena } from '@/components/PravnoNapomena';
import { KONTAKT_EMAIL } from '@/lib/config';

export const metadata: Metadata = { title: 'Kontakt', alternates: { canonical: '/kontakt' } };

export default function Kontakt() {
  return (
    <>
    <Traka naslov="Kontakt" natrag="/profil" h1={false} />
    <article className="pravno">
      <h1 className="sr-only">Kontakt</h1>
      <PravnoNapomena />
      <p>Pitanja, prijave i zahtjevi u vezi s podacima: <a href={`mailto:${KONTAKT_EMAIL}`}>{KONTAKT_EMAIL}</a></p>
      <p>Sumnjiv oglas najbrže prijaviš gumbom &quot;Prijavi oglas&quot; na samom oglasu. Više u <Link href="/uvjeti">Uvjetima korištenja</Link>.</p>
      <p className="pomoc">Ovdje dodaj naziv i adresu osobe koja vodi stranicu (obavezno prema zakonu).</p>
    </article>
    </>
  );
}
