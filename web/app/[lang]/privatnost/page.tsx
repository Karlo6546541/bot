import type { Metadata } from 'next';
import Link from 'next/link';
import { PravnaStranica } from '@/components/PravnaStranica';
import { alternative, jezik, prevedi, put } from '@/lib/i18n';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const j = jezik((await params).lang);
  return { title: prevedi(j, 'Politika privatnosti'), alternates: alternative(j, '/privatnost') };
}

export default async function Privatnost({ params }: { params: P }) {
  const j = jezik((await params).lang);
  if (j === 'en') {
    return (
      <PravnaStranica naslov="Privacy policy">
        <h2>What we collect</h2>
        <ul>
          <li>Account data: e-mail, name or nickname, country and city, and optionally a phone number. With Google sign-in we receive the name and e-mail of the Google account.</li>
          <li>Content you post: listings with location, photos, messages and reports.</li>
          <li>Contact history per listing (who sent a message or viewed the phone number) and sale details, for statistics.</li>
        </ul>
        <h2>Why</h2>
        <p>To run the classifieds (posting, search, messages), for safety and moderation, and for aggregate statistics.</p>
        <h2>Who sees the data</h2>
        <ul>
          <li>Your name, city and sign-up date are shown on your listings.</li>
          <li>Your phone number is shown only to signed-in users and only on listings where you choose so.</li>
          <li>Messages are visible only to the people in the conversation.</li>
          <li>Data is stored with the database provider (Supabase) and the site is served by Vercel.</li>
        </ul>
        <h2>Your rights</h2>
        <p>You can request access to, correction or deletion of your data through the <Link href={put(j, '/kontakt')}>Contact</Link> page.</p>
        <h2>Cookies</h2>
        <p>We only use cookies needed for signing in and for your language choice. We do not use advertising or tracking cookies.</p>
      </PravnaStranica>
    );
  }
  return (
    <PravnaStranica naslov="Politika privatnosti">
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
        <li>Podaci se čuvaju kod pružatelja baze podataka (Supabase), a stranicu poslužuje Vercel.</li>
      </ul>
      <h2>Tvoja prava</h2>
      <p>Uvid, ispravak ili brisanje podataka možeš zatražiti preko stranice <Link href={put(j, '/kontakt')}>Kontakt</Link>.</p>
      <h2>Kolačići</h2>
      <p>Koristimo samo nužne kolačiće za prijavu i odabir jezika. Ne koristimo kolačiće za oglašavanje ni praćenje.</p>
    </PravnaStranica>
  );
}
