// Mali omotač oko IndexedDB-a za lokalni (demo) način rada.
const TABLICE = [
  'korisnici',
  'oglasi',
  'favoriti',
  'razgovori',
  'poruke',
  'kontakti',
  'prijave',
] as const;
export type Tablica = (typeof TABLICE)[number];

let baza: Promise<IDBDatabase> | null = null;

function otvori(): Promise<IDBDatabase> {
  baza ??= new Promise((ok, greska) => {
    const r = indexedDB.open('oglasnik', 1);
    r.onupgradeneeded = () => {
      for (const t of TABLICE) {
        if (!r.result.objectStoreNames.contains(t)) r.result.createObjectStore(t, { keyPath: 'id' });
      }
    };
    r.onsuccess = () => ok(r.result);
    r.onerror = () => greska(r.error);
  });
  return baza;
}

async function zahtjev<T>(t: Tablica, nacin: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest): Promise<T> {
  const db = await otvori();
  return new Promise((ok, greska) => {
    const r = fn(db.transaction(t, nacin).objectStore(t));
    r.onsuccess = () => ok(r.result as T);
    r.onerror = () => greska(r.error);
  });
}

export const sve = <T>(t: Tablica) => zahtjev<T[]>(t, 'readonly', (s) => s.getAll());
export const jedan = <T>(t: Tablica, id: string) =>
  zahtjev<T | undefined>(t, 'readonly', (s) => s.get(id));
export const spremi = <T extends { id: string }>(t: Tablica, v: T) =>
  zahtjev<IDBValidKey>(t, 'readwrite', (s) => s.put(v)).then(() => v);
export const izbrisi = (t: Tablica, id: string) =>
  zahtjev<undefined>(t, 'readwrite', (s) => s.delete(id));

/** Samo za testove: zatvori i obriši bazu. */
export async function _resetiraj() {
  if (baza) (await baza).close();
  baza = null;
  await new Promise((ok) => {
    const r = indexedDB.deleteDatabase('oglasnik');
    r.onsuccess = r.onerror = r.onblocked = ok;
  });
}
