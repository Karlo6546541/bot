import { APP_NAME, SITE_URL } from './config';
import { kategorija } from './kategorije';
import { lokacijaTekst, nazivDrzave } from './lokacije';
import { slug } from './tekst';
import type { Oglas } from './types';

export const putOglasa = (o: Pick<Oglas, 'id' | 'naslov'>) => `/oglas/${o.id}/${slug(o.naslov)}`;
export const punaAdresa = (put: string) => `${SITE_URL}${put}`;

const STANJE_SCHEMA: Record<string, string> = {
  Novo: 'https://schema.org/NewCondition',
  'Kao novo': 'https://schema.org/UsedCondition',
  Dobro: 'https://schema.org/UsedCondition',
  Oštećeno: 'https://schema.org/DamagedCondition',
};

/** Strukturirani podaci za stranicu oglasa (Product + Offer) za Google. */
export function jsonLdOglas(o: Oglas) {
  const kat = kategorija(o.kategorija);
  const ponuda: Record<string, unknown> = {
    '@type': 'Offer',
    url: punaAdresa(putOglasa(o)),
    availability: o.status === 'aktivan' ? 'https://schema.org/InStock' : 'https://schema.org/SoldOut',
    itemCondition: STANJE_SCHEMA[o.stanje],
    availableAtOrFrom: {
      '@type': 'Place',
      address: {
        '@type': 'PostalAddress',
        addressLocality: o.grad,
        ...(o.zupanija ? { addressRegion: o.zupanija } : {}),
        addressCountry: o.drzava === 'XX' ? undefined : o.drzava,
      },
    },
  };
  // Bez cijene ("dogovor") se ne objavljuje cijena, da se ne lažu strukturirani podaci.
  if (o.cijena != null) {
    ponuda.price = o.cijena.toFixed(2);
    ponuda.priceCurrency = 'EUR';
  }
  return {
    '@context': 'https://schema.org',
    '@type': 'Product',
    name: o.naslov,
    description: o.opis.slice(0, 500),
    image: o.slike,
    category: kat?.naziv,
    sku: o.id,
    offers: ponuda,
  };
}

export function jsonLdPutanja(stavke: { naziv: string; put: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: stavke.map((s, i) => ({ '@type': 'ListItem', position: i + 1, name: s.naziv, item: punaAdresa(s.put) })),
  };
}

export function jsonLdStranica() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: APP_NAME,
    url: SITE_URL,
    potentialAction: {
      '@type': 'SearchAction',
      target: `${SITE_URL}/oglasi?q={search_term_string}`,
      'query-input': 'required name=search_term_string',
    },
  };
}

/** Sigurno ugrađivanje JSON-a u <script> (sprječava zatvaranje oznake). */
export const jsonUScript = (o: unknown) => JSON.stringify(o).replace(/</g, '\\u003c');

export function opisOglasa(o: Oglas): string {
  const kat = kategorija(o.kategorija)?.naziv ?? '';
  const cijena = o.cijena == null ? 'Cijena po dogovoru' : `${o.cijena} €`;
  const pocetak = `${o.naslov}: ${kat}, ${o.stanje}, ${cijena}, ${lokacijaTekst(o)}. `;
  return (pocetak + o.opis).replace(/\s+/g, ' ').slice(0, 158);
}

export { nazivDrzave };
