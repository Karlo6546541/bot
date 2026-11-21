import type { Metadata } from 'next';
import { PravnoNapomena } from '@/components/PravnoNapomena';
import { KONTAKT_EMAIL } from '@/lib/config';

export const metadata: Metadata = { title: 'Politika privatnosti', alternates: { canonical: '/privatnost' } };

export default function Privatnost() {
  return (
    <article className="pravno">
      <h1>Politika privatnosti</h1>
      <PravnoNapomena />
      <h2>Koje podatke prikupljamo</h2>
      <ul>
        <li>Podatke računa: e-mail, ime ili nadimak, država i grad, po želji broj telefona. Kod prijave Googleom primamo ime i e-mail s Google računa.</li>
        <li>Sadržaj koji objaviš: oglase s lokacijom, fotografije, poruke i prijave oglasa.</li>
        <li>Povijest kontakata po oglasu (tko je poslao poruku ili pogledao telefon) i podatke o prodaji, za statistiku.</li>
      </ul>
      <h2>Zašto</h2>
      <p>Da bi oglasnik radio (objava, pretraga, poruke), radi sigurnosti i moderacije te za zbirnu statistiku.</p>
      <h2>Tko vidi podatke</h2>
      <ul>
        <li>Ime, grad i datum registracije vidljivi su na tvojim oglasima.</li>
        <li>Telefon vide samo prijavljeni korisnici i samo na oglasima na kojima to odabereš.</li>
        <li>Poruke vide samo sudionici razgovora.</li>
        <li>Podaci se čuvaju kod pružatelja baze podataka (Supabase), a stranicu poslužuje Vercel. Lokacije poslužitelja ovise o postavkama projekta.</li>
      </ul>
      <h2>Tvoja prava</h2>
      <p>Možeš zatražiti uvid, ispravak ili brisanje podataka na <a href={`mailto:${KONTAKT_EMAIL}`}>{KONTAKT_EMAIL}</a>. Račun možeš zatražiti obrisati u Profilu.</p>
      <h2>Kolačići</h2>
      <p>Koristimo samo nužne kolačiće za prijavu. Ne koristimo kolačiće za oglašavanje ni praćenje.</p>
    </article>
  );
}
