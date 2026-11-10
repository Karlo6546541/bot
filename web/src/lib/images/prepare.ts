/**
 * Client-side image preparation: downscale + convert to WebP before upload,
 * so readers on slow mobile connections download small files.
 */
export interface PreparedImage {
  blob: Blob;
  width: number;
  height: number;
}

export async function prepareImage(file: File, maxWidth: number, quality = 0.85): Promise<PreparedImage> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxWidth / bitmap.width);
  const width = Math.round(bitmap.width * scale);
  const height = Math.round(bitmap.height * scale);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("canvas unsupported");
  ctx.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();
  const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, "image/webp", quality));
  // Safari < 16 cannot encode WebP; fall back to JPEG.
  if (blob && blob.type === "image/webp") return { blob, width, height };
  const jpeg = await new Promise<Blob | null>((res) => canvas.toBlob(res, "image/jpeg", quality));
  if (!jpeg) throw new Error("encode failed");
  return { blob: jpeg, width, height };
}

export const extFor = (blob: Blob) => (blob.type === "image/webp" ? "webp" : "jpg");

/** Natural sort so "page-2" comes before "page-10". */
export function naturalCompare(a: string, b: string) {
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
}
