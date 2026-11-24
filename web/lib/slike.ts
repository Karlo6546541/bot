import { SLIKA_MALA_PX, SLIKA_PX } from './config';

/** Smanji sliku u pregledniku (WebP, rezervno JPEG) prije slanja. */
async function smanji(bitmap: ImageBitmap, najvise: number, kvaliteta: number): Promise<Blob> {
  const omjer = Math.min(1, najvise / Math.max(bitmap.width, bitmap.height));
  const w = Math.max(1, Math.round(bitmap.width * omjer));
  const h = Math.max(1, Math.round(bitmap.height * omjer));
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d')!;
  ctx.drawImage(bitmap, 0, 0, w, h);
  const blob = await new Promise<Blob | null>((ok) => c.toBlob(ok, 'image/webp', kvaliteta));
  if (blob && blob.type === 'image/webp') return blob;
  return new Promise<Blob>((ok, greska) =>
    c.toBlob((b) => (b ? ok(b) : greska(new Error('Slika se ne može obraditi.'))), 'image/jpeg', kvaliteta),
  );
}

export async function pripremiSliku(f: File): Promise<{ velika: Blob; mala: Blob; pregled: string }> {
  if (!f.type.startsWith('image/')) throw new Error('Datoteka nije slika.');
  const bitmap = await createImageBitmap(f, { imageOrientation: 'from-image' });
  try {
    const velika = await smanji(bitmap, SLIKA_PX, 0.82);
    const mala = await smanji(bitmap, SLIKA_MALA_PX, 0.75);
    return { velika, mala, pregled: URL.createObjectURL(mala) };
  } finally {
    bitmap.close();
  }
}
