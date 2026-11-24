// Osnovne postavke aplikacije. Ime i slogan mijenjaju se ovdje ili kroz
// varijable okruženja (VITE_APP_NAME, VITE_APP_SLOGAN) pri buildu.
export const APP_NAME: string = import.meta.env.VITE_APP_NAME || 'Subhasto';
export const APP_SLOGAN: string =
  import.meta.env.VITE_APP_SLOGAN || 'Oglasnik za kolekcionare';
export const KONTAKT_EMAIL: string =
  import.meta.env.VITE_CONTACT_EMAIL || 'kontakt@primjer.hr';

/** Koliko dana oglas traje prije isteka (i koliko ga produži "Produlji"). */
export const ISTEK_DANA = 30;
/** Najviše fotografija po oglasu (najmanje jedna je obavezna). */
export const MAX_SLIKA = 8;
/** Broj oglasa po stranici popisa. */
export const PO_STRANICI = 24;
/** Najdulja stranica slike (px) nakon smanjivanja i umanjenog prikaza. */
export const SLIKA_PX = 1600;
export const SLIKA_MALA_PX = 480;
