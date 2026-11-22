import type { Metadata } from 'next';
import { PravnaStranica } from '@/components/PravnaStranica';
import { APP_NAME, ISTEK_DANA } from '@/lib/config';
import { alternative, jezik, prevedi } from '@/lib/i18n';

type P = Promise<{ lang: string }>;
export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const j = jezik((await params).lang);
  return { title: prevedi(j, 'Uvjeti korištenja'), alternates: alternative(j, '/uvjeti') };
}

export default async function Uvjeti({ params }: { params: P }) {
  const j = jezik((await params).lang);
  if (j === 'en') {
    return (
      <PravnaStranica naslov="Terms of use">
        <h2>1. What {APP_NAME} is</h2>
        <p>{APP_NAME} is a classifieds site where users post listings for collectibles and interested buyers send them a message. {APP_NAME} is not a party to any sale: it does not sell items, receive money or arrange delivery or payment. Price, payment and handover are agreed directly between buyer and seller, outside the site.</p>
        <h2>2. Account</h2>
        <p>An account is needed to post listings and send messages. Account details must be accurate and the user is responsible for keeping their password safe. Accounts are intended for private individuals.</p>
        <h2>3. Listings</h2>
        <ul>
          <li>A listing must describe a real item you are allowed to sell, with real photos and an accurate location (country, county and city).</li>
          <li>Counterfeits, stolen goods and anything prohibited by law are not allowed.</li>
          <li>A listing is active for {ISTEK_DANA} days and can be renewed or marked as sold.</li>
          <li>The seller is responsible for the description, condition and price of the item.</li>
        </ul>
        <h2>4. Fees</h2>
        <p>Posting listings and using the site are free.</p>
        <h2>5. Moderation and reports</h2>
        <p>Any listing can be reported for fraud, counterfeits or inappropriate content. Listings or accounts that break these terms may be removed or restricted.</p>
        <h2>6. Liability</h2>
        <p>{APP_NAME} gives no guarantee for items, users or the outcome of any deal. We recommend meeting in person and being careful with payment in advance.</p>
      </PravnaStranica>
    );
  }
  return (
    <PravnaStranica naslov="Uvjeti korištenja">
      <h2>1. Što je {APP_NAME}</h2>
      <p>{APP_NAME} je oglasnik na kojem korisnici objavljuju oglase za kolekcionarske predmete, a zainteresirani im pišu poruku. {APP_NAME} nije strana u kupoprodaji: ne prodaje predmete, ne prima novac i ne organizira dostavu ni plaćanje. Cijenu, plaćanje i preuzimanje kupac i prodavatelj dogovaraju izravno, izvan stranice.</p>
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
      <p>Svaki oglas može se prijaviti zbog prevare, krivotvorine ili neprimjerenog sadržaja. Oglas ili račun koji krši ove uvjete može se ukloniti ili ograničiti.</p>
      <h2>6. Odgovornost</h2>
      <p>{APP_NAME} ne jamči za predmete, korisnike ni ishod dogovora. Preporučujemo osobno preuzimanje i oprez kod plaćanja unaprijed.</p>
    </PravnaStranica>
  );
}
