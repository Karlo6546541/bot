import { SITE_URL } from './config';

/** IndexNow ključ (datoteka public/<ključ>.txt dokazuje vlasništvo nad domenom). */
export const INDEXNOW_KLJUC = '7195c3e9e7346107a94bbc3741b591b6';

/** Javlja Bingu, Yandexu, Seznamu i Naveru da je stranica nova ili promijenjena (odmah indeksiranje). */
export async function javiIndexNow(adrese: string[]) {
  if (!SITE_URL.startsWith('https://') || !adrese.length) return;
  const host = new URL(SITE_URL).host;
  try {
    await fetch('https://api.indexnow.org/indexnow', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify({ host, key: INDEXNOW_KLJUC, keyLocation: `${SITE_URL}/${INDEXNOW_KLJUC}.txt`, urlList: adrese.map((a) => `${SITE_URL}${a}`) }),
      signal: AbortSignal.timeout(5000),
    });
  } catch (e) {
    console.error('IndexNow:', (e as Error).message);
  }
}
