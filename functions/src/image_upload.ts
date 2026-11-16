import { HttpsError } from 'firebase-functions/https';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { randomBytes, randomUUID } from 'node:crypto';

/**
 * Server-side image upload proxy to Firebase Storage.
 *
 * Uploads are verified (file size, MIME sniff), rate-limited per user, and stored
 * directly in Firebase Storage. Returns a permanent download URL with a download token.
 */

export const MAX_IMAGE_BYTES = 7 * 1024 * 1024; // callable request bodies are capped at 10 MB (base64 adds ~33%)
export const HOURLY_UPLOADS = 60;

export interface StorageFileLike {
  save(data: Buffer, options?: { metadata?: { contentType?: string; metadata?: Record<string, string> } }): Promise<void>;
}

export interface StorageBucketLike {
  name: string;
  file(path: string): StorageFileLike;
}

export interface UploadDeps {
  db: Firestore;
  bucket: StorageBucketLike;
  now: () => number;
  randomId?: () => string;
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

  // Per-user hourly cap (counts attempts, so a stuck client cannot hammer the host).
  const bucketHour = Math.floor(deps.now() / 3_600_000);
  const ref = deps.db.doc(`image_upload_limits/${uid}_${bucketHour}`);
  const over = await deps.db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const n = (snap.exists ? (snap.get('count') as number) : 0) || 0;
    if (n >= HOURLY_UPLOADS) return true;
    t.set(ref, { uid, count: FieldValue.increment(1), bucket: bucketHour }, { merge: true });
    return false;
  });
  if (over) throw new HttpsError('resource-exhausted', 'Too many uploads. Please try again later.');

  const imageKind = sniffImage(input.bytes);
  if (!imageKind) throw new HttpsError('invalid-argument', 'Only JPEG, PNG, GIF or WebP images can be uploaded.');

  const ext = imageKind === 'jpeg' ? 'jpg' : imageKind;
  const mimeType = `image/${imageKind}`;
  const token = deps.randomId ? deps.randomId() : randomUUID();
  const hex = randomBytes(4).toString('hex');
  const safeName = input.name ? `${input.name}_${hex}.${ext}` : `${deps.now()}_${hex}.${ext}`;
  const filePath = `uploads/${uid}/${safeName}`;

  try {
    const file = deps.bucket.file(filePath);
    await file.save(input.bytes, {
      metadata: {
        contentType: mimeType,
        metadata: {
          firebaseStorageDownloadTokens: token,
        },
      },
    });
  } catch {
    throw new HttpsError('unavailable', 'Firebase Storage is unavailable. Please try again.');
  }

  const bucketName = deps.bucket.name || 'tranyx-app.firebasestorage.app';
  const encodedPath = encodeURIComponent(filePath);
  const url = `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucketName)}/o/${encodedPath}?alt=media&token=${token}`;
  return { url };
}
