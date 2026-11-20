import { APP_NAME, APP_SLOGAN } from '../config/app';

function meta(atribut: 'name' | 'property', kljuc: string, vrijednost: string) {
  let m = document.head.querySelector<HTMLMetaElement>(`meta[${atribut}="${kljuc}"]`);
  if (!m) {
    m = document.createElement('meta');
    m.setAttribute(atribut, kljuc);
    document.head.appendChild(m);
  }
  m.content = vrijednost;
}

/** Naslov, opis i kanonska adresa za trenutnu stranicu. */
export function postaviSeo(naslov: string | null, opis?: string, slika?: string) {
  const puni = naslov ? `${naslov} | ${APP_NAME}` : `${APP_NAME} – ${APP_SLOGAN}`;
  document.title = puni;
  const o = (opis ?? `${APP_NAME}: ${APP_SLOGAN.toLowerCase()}. Kartice, kovanice, marke, stripovi, figurice i ploče.`)
    .replace(/\s+/g, ' ')
    .slice(0, 160);
  meta('name', 'description', o);
  meta('property', 'og:title', puni);
  meta('property', 'og:description', o);
  if (slika) meta('property', 'og:image', slika);
  let c = document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]');
  if (!c) {
    c = document.createElement('link');
    c.rel = 'canonical';
    document.head.appendChild(c);
  }
  c.href = location.origin + location.pathname;
}
