import type { Metadata } from 'next';
import { PravnoNapomena } from '@/components/PravnoNapomena';
import { APP_NAME, ISTEK_DANA } from '@/lib/config';

export const metadata: Metadata = { title: 'Uvjeti korištenja', alternates: { canonical: '/uvjeti' } };

export default function Uvjeti() {
  return (
    <article className="pravno">
      <h1>Uvjeti korištenja</h1>
      <PravnoNapomena />
      <h2>1. Što je {APP_NAME}</h2>
      <p>
        {APP_NAME} je oglasnik na kojem korisnici objavljuju oglase za kolekcionarske predmete, a zainteresirani im pišu poruku. {APP_NAME} nije strana u kupoprodaji: ne prodaje predmete, ne prima novac i ne organizira dostavu ni plaćanje. Cijenu, plaćanje i preuzimanje kupac i prodavatelj dogovaraju izravno, izvan stranice.
      </p>
      <h2>2. Račun</h2>
      <p>Za objavu oglasa i slanje poruka potreban je račun. Podaci moraju biti točni, a za sigurnost lozinke odgovara korisnik. Račun je namijenjen privatnim osobama.</p>
      <h2>3. Oglasi</h2>
      <ul>
        <li>Oglas mora opisivati stvaran predmet koji smiješ prodati, sa stvarnim fotografijama i točnom lokacijom (država, županija i grad).</li>
        <li>Zabranjeni su krivotvoreni predmeti, ukradena roba i sve što je zakonom zabranjeno.</li>
        <li>Oglas je aktivan {ISTEK_DANA} dana i može se produljiti ili označiti kao prodan.</li>
        <li>Prodavatelj odgovara za opis, stanje i cijenu predmeta.</li>
      </ul>
      <h2>4. Naknade</h2>
      <p>Objava oglasa i korištenje oglasnika su besplatni.</p>
      <h2>5. Moderacija i prijave</h2>
      <p>Svaki oglas može se prijaviti zbog prevare, krivotvorine ili neprimjerenog sadržaja. Oglas ili račun koji krši ove uvjete možemo ukloniti ili ograničiti; o odluci obavještavamo korisnika s razlogom.</p>
      <h2>6. Odgovornost</h2>
      <p>{APP_NAME} ne jamči za predmete, korisnike ni ishod dogovora. Preporučujemo osobno preuzimanje i oprez kod plaćanja unaprijed.</p>
      <h2>7. Izdavatelj</h2>
      <p>[NAZIV TVRTKE ILI IME FIZIČKE OSOBE], [OIB], [ADRESA SJEDIŠTA], [KONTAKT E-MAIL].</p>
    </article>
  );
}
