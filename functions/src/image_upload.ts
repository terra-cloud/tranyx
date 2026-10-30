import { HttpsError } from 'firebase-functions/https';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';

/**
 * Server-side image upload proxy (replaces browser -> api.imgbb.com).
 *
 * Why: imgbb's API sends no usable CORS answer for its error / gateway-timeout responses, so the browser
 * reports every failure as "blocked by CORS policy" and the real reason is hidden. The IMGBB key was also
 * shipped to every visitor inside the web bundle. The browser now sends the image to this callable
 * (signed-in users only); the key stays in Secret Manager and the response is a clean URL or a clear error.
 */

export const MAX_IMAGE_BYTES = 7 * 1024 * 1024; // callable request bodies are capped at 10 MB (base64 adds ~33%)
export const HOURLY_UPLOADS = 60;
export const UPLOAD_TIMEOUT_MS = 25_000;

export type FetchLike = (url: string, init: { method: string; body: string; headers: Record<string, string>; signal: AbortSignal }) => Promise<{
  ok: boolean;
  status: number;
  text(): Promise<string>;
}>;

export interface UploadDeps {
  db: Firestore;
  fetchFn: FetchLike;
  apiKey: string;
  now: () => number;
}

export function sniffImage(b: Buffer): 'jpeg' | 'png' | 'gif' | 'webp' | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpeg';
  if (b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (b.length >= 6 && (b.subarray(0, 6).toString('latin1') === 'GIF87a' || b.subarray(0, 6).toString('latin1') === 'GIF89a')) return 'gif';
  if (b.length >= 12 && b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP') return 'webp';
  return null;
}

export interface ParsedUpload {
  bytes: Buffer;
  base64: string;
  name: string;
}

export function parseUploadInput(data: unknown): ParsedUpload {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const raw = typeof d.imageBase64 === 'string' ? d.imageBase64.replace(/^data:[^;]+;base64,/, '') : '';
  if (!raw || raw.length > Math.ceil((MAX_IMAGE_BYTES * 4) / 3) + 8 || !/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) {
    throw new HttpsError('invalid-argument', 'imageBase64 must be a base64 image of at most 7 MB.');
  }
  const bytes = Buffer.from(raw, 'base64');
  if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) throw new HttpsError('invalid-argument', 'The image is empty or larger than 7 MB.');
  if (!sniffImage(bytes)) throw new HttpsError('invalid-argument', 'Only JPEG, PNG, GIF or WebP images can be uploaded.');
  const name = typeof d.name === 'string' ? d.name.replace(/\.[A-Za-z0-9]+$/, '').replace(/[^\w.-]+/g, '_').slice(0, 60) : '';
  return { bytes, base64: raw, name };
}

export async function uploadImage(deps: UploadDeps, uid: string | undefined, data: unknown): Promise<{ url: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to upload images.');
  const input = parseUploadInput(data);
  if (!deps.apiKey) throw new HttpsError('failed-precondition', 'Image upload is not configured.');

  // Per-user hourly cap (counts attempts, so a stuck client cannot hammer the host).
  const bucket = Math.floor(deps.now() / 3_600_000);
  const ref = deps.db.doc(`image_upload_limits/${uid}_${bucket}`);
  const over = await deps.db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const n = (snap.exists ? (snap.get('count') as number) : 0) || 0;
    if (n >= HOURLY_UPLOADS) return true;
    t.set(ref, { uid, count: FieldValue.increment(1), bucket }, { merge: true });
    return false;
  });
  if (over) throw new HttpsError('resource-exhausted', 'Too many uploads. Please try again later.');

  const body = new URLSearchParams({ key: deps.apiKey, image: input.base64 });
  if (input.name) body.set('name', input.name);
  let res;
  try {
    res = await deps.fetchFn('https://api.imgbb.com/1/upload', {
      method: 'POST',
      body: body.toString(),
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      signal: AbortSignal.timeout(UPLOAD_TIMEOUT_MS),
    });
  } catch {
    throw new HttpsError('unavailable', 'The image host did not respond. Please try again.');
  }
  const text = await res.text().catch(() => '');
  let json: any = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* not JSON: gateway page */
  }
  const url = json?.data?.url ?? json?.data?.display_url;
  if (res.ok && typeof url === 'string' && /^https:\/\//.test(url)) return { url };
  // Never forward the host's body (it can echo the key). Map to a clear, fixed message.
  if (res.status === 400 || res.status === 403) throw new HttpsError('failed-precondition', 'The image host rejected the upload (check the image service key).');
  if (res.status === 429) throw new HttpsError('resource-exhausted', 'The image host is rate limiting uploads. Please try again shortly.');
  throw new HttpsError('unavailable', 'The image host is unavailable. Please try again.');
}
