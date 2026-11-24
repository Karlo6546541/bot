import { useEffect } from 'preact/hooks';
import { APP_NAME, ISTEK_DANA, KONTAKT_EMAIL } from '../config/app';
import { adresa } from '../lib/router';
import { postaviSeo } from '../lib/seo';

// PREDLOŠCI: tekstove mora pregledati pravnik prije javnog pokretanja.
function Napomena() {
  return (
    <p class="napomena">
      <b>Predložak.</b> Ovaj tekst je radna verzija i prije javnog pokretanja mora ga pregledati pravnik.
    </p>
  );
}

export function Uvjeti() {
  useEffect(() => postaviSeo('Uvjeti korištenja'), []);
  return (
    <article class="pravno">
      <h1>Uvjeti korištenja</h1>
      <Napomena />
      <h2>1. Što je {APP_NAME}</h2>
      <p>
        {APP_NAME} je oglasnik na kojem korisnici objavljuju oglase za kolekcionarske predmete. {APP_NAME} nije strana u
        kupoprodaji: ne prodaje predmete, ne prima novac i ne organizira dostavu. Dogovor o cijeni, plaćanju i preuzimanju
        sklapaju kupac i prodavatelj izravno.
      </p>
      <h2>2. Korisnički račun</h2>
      <p>
        Za objavu oglasa i slanje poruka potreban je račun. Korisnik je odgovoran za točnost podataka i za sve radnje
        učinjene s njegovog računa.
      </p>
      <h2>3. Oglasi</h2>
      <ul>
        <li>Oglas mora opisivati stvarni predmet koji korisnik smije prodati, sa stvarnim fotografijama.</li>
        <li>Zabranjeni su krivotvoreni predmeti, ukradena roba i predmeti čija je prodaja zakonom zabranjena.</li>
        <li>Oglas je aktivan {ISTEK_DANA} dana i može se produljiti.</li>
        <li>Prodavatelj odgovara za opis, stanje i cijenu predmeta.</li>
      </ul>
      <h2>4. Moderacija</h2>
      <p>
        {APP_NAME} može ukloniti oglas ili blokirati račun koji krši ove uvjete, posebno kod prijava prevare ili
        krivotvorina.
      </p>
      <h2>5. Odgovornost</h2>
      <p>
        {APP_NAME} ne jamči za predmete, korisnike ni ishod dogovora. Preporučujemo osobno preuzimanje i oprez kod
        plaćanja unaprijed.
      </p>
      <h2>6. Promjene uvjeta</h2>
      <p>O bitnim promjenama uvjeta korisnike ćemo obavijestiti na stranici.</p>
    </article>
  );
}

export function Privatnost() {
  useEffect(() => postaviSeo('Politika privatnosti'), []);
  return (
    <article class="pravno">
      <h1>Politika privatnosti</h1>
      <Napomena />
      <h2>Koje podatke prikupljamo</h2>
      <ul>
        <li>Podatke računa: e-mail, ime ili nadimak, grad, po želji broj telefona.</li>
        <li>Sadržaj koji objaviš: oglase, fotografije, poruke i prijave oglasa.</li>
        <li>Povijest kontakata po oglasu (tko je poslao poruku ili pogledao telefon) i podatke o prodaji, za statistiku.</li>
      </ul>
      <h2>Zašto</h2>
      <p>Da bi oglasnik radio (objava, pretraga, poruke), radi sigurnosti i moderacije te za zbirnu statistiku.</p>
      <h2>Tko vidi podatke</h2>
      <ul>
        <li>Ime, grad i datum registracije vidljivi su na tvojim oglasima.</li>
        <li>Telefon vide samo prijavljeni korisnici i samo na oglasima na kojima to odabereš.</li>
        <li>Poruke vide samo sudionici razgovora.</li>
        <li>Podaci se čuvaju kod pružatelja usluge baze podataka (Supabase) u EU ili SAD-u, ovisno o postavkama projekta.</li>
      </ul>
      <h2>Tvoja prava</h2>
      <p>
        Možeš zatražiti uvid, ispravak ili brisanje podataka na <a href={`mailto:${KONTAKT_EMAIL}`}>{KONTAKT_EMAIL}</a>.
      </p>
      <h2>Kolačići i lokalna pohrana</h2>
      <p>Koristimo samo nužnu lokalnu pohranu za prijavu. Ne koristimo kolačiće za oglašavanje.</p>
    </article>
  );
}

export function Kontakt() {
  useEffect(() => postaviSeo('Kontakt'), []);
  return (
    <article class="pravno">
      <h1>Kontakt</h1>
      <Napomena />
      <p>
        Pitanja, prijave i zahtjevi u vezi s podacima: <a href={`mailto:${KONTAKT_EMAIL}`}>{KONTAKT_EMAIL}</a>
      </p>
      <p>
        Sumnjiv oglas najbrže prijaviš gumbom "Prijavi oglas" na samom oglasu. Za opće informacije pogledaj{' '}
        <a href={adresa('/uvjeti')}>Uvjete korištenja</a>.
      </p>
      <p class="pomoc">Ovdje dodaj naziv i adresu pravne ili fizičke osobe koja vodi stranicu (obavezno prema zakonu).</p>
    </article>
  );
}

export function NijePronadeno() {
  useEffect(() => postaviSeo('Stranica nije pronađena'), []);
  return (
    <div class="prazno ploca">
      <h1>Stranica nije pronađena</h1>
      <a class="gumb" href={adresa('/')}>
        Na početnu
      </a>
    </div>
  );
}
