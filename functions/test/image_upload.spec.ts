import { beforeEach, describe, expect, it } from 'vitest';
import type { Firestore } from 'firebase-admin/firestore';
import {
  HOURLY_UPLOADS,
  MAX_IMAGE_BYTES,
  parseUploadInput,
  sniffImage,
  uploadImage,
  type StorageBucketLike,
  type StorageFileLike,
  type UploadDeps,
} from '../src/image_upload';

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32, 1)]);
const png64 = PNG.toString('base64');
const err = async (p: Promise<unknown>) => p.then(() => null, (e) => e as { code: string; message: string });

let savedFiles: { path: string; bytes: Buffer; options?: any }[] = [];
let saveShouldThrow = false;

const mockBucket: StorageBucketLike = {
  name: 'tranyx-app.firebasestorage.app',
  file(path: string): StorageFileLike {
    return {
      save: async (bytes: Buffer, options?: any) => {
        if (saveShouldThrow) throw new Error('Google Cloud Storage connection refused');
        savedFiles.push({ path, bytes, options });
      },
    };
  },
};

let store = new Map<string, any>();
function createMockDb(): Firestore {
  return {
    doc(path: string) {
      return { path };
    },
    runTransaction: async (fn: any) => {
      const transaction = {
        get: async (ref: any) => ({
          exists: store.has(ref.path),
          get: (f: string) => store.get(ref.path)?.[f],
        }),
        set: (ref: any, data: any) => {
          const prev = store.get(ref.path) || {};
          const next = { ...prev, ...data };
          if (data.count && typeof data.count === 'object') {
            next.count = (prev.count || 0) + 1;
          }
          store.set(ref.path, next);
        },
      };
      return await fn(transaction);
    },
  } as unknown as Firestore;
}

let clock = Date.UTC(2026, 9, 31, 4, 0, 0);
let db = createMockDb();
const deps = (): UploadDeps => ({
  db,
  bucket: mockBucket,
  now: () => clock,
  randomId: () => 'fixed-token-uuid-123',
});

beforeEach(() => {
  store.clear();
  savedFiles = [];
  saveShouldThrow = false;
  clock = Date.UTC(2026, 9, 31, 4, 0, 0);
  db = createMockDb();
});

describe('input checks', () => {
  it('sniffs real image types and refuses everything else', () => {
    expect(sniffImage(PNG)).toBe('png');
    expect(sniffImage(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).toBe('jpeg');
    expect(sniffImage(Buffer.from('GIF89a....'))).toBe('gif');
    expect(sniffImage(Buffer.concat([Buffer.from('RIFF'), Buffer.alloc(4), Buffer.from('WEBP')]))).toBe('webp');
    expect(sniffImage(Buffer.from('<svg onload=alert(1)>'))).toBeNull();
    expect(sniffImage(Buffer.from('%PDF-1.7'))).toBeNull();
  });

  it('parses data URLs, strips the extension from the name, rejects junk and oversize', () => {
    expect(parseUploadInput({ imageBase64: `data:image/png;base64,${png64}`, name: 'my photo (1).PNG' }).name).toBe('my_photo_1_');
    expect(() => parseUploadInput({})).toThrow();
    expect(() => parseUploadInput({ imageBase64: 'not base64!!' })).toThrow();
    expect(() => parseUploadInput({ imageBase64: Buffer.from('plain text file').toString('base64') })).toThrow(/Only JPEG/);
    const big = Buffer.concat([PNG, Buffer.alloc(MAX_IMAGE_BYTES)]).toString('base64');
    expect(() => parseUploadInput({ imageBase64: big })).toThrow();
  });
});

describe('uploadImage to Firebase Storage', () => {
  it('needs a signed-in user', async () => {
    expect((await err(uploadImage(deps(), undefined, { imageBase64: png64 })))?.code).toBe('unauthenticated');
    expect(savedFiles).toHaveLength(0);
  });

  it('saves file to Firebase Storage bucket and returns public download URL with token', async () => {
    const res = await uploadImage(deps(), 'user123', { imageBase64: png64, name: 'receipt.png' });
    expect(savedFiles).toHaveLength(1);
    expect(savedFiles[0].path).toMatch(/^uploads\/user123\/receipt_[a-f0-9]+\.png$/);
    expect(savedFiles[0].options?.metadata?.contentType).toBe('image/png');
    expect(savedFiles[0].options?.metadata?.metadata?.firebaseStorageDownloadTokens).toBe('fixed-token-uuid-123');

    expect(res.url).toContain('https://firebasestorage.googleapis.com/v0/b/tranyx-app.firebasestorage.app/o/uploads%2Fuser123%2Freceipt_');
    expect(res.url).toContain('?alt=media&token=fixed-token-uuid-123');
  });

  it('handles storage errors gracefully', async () => {
    saveShouldThrow = true;
    const e = await err(uploadImage(deps(), 'user123', { imageBase64: png64 }));
    expect(e?.code).toBe('unavailable');
    expect(e?.message).toContain('Firebase Storage is unavailable');
  });

  it('caps uploads per user per hour and resets the next hour', async () => {
    for (let i = 0; i < HOURLY_UPLOADS; i++) {
      await uploadImage(deps(), 'u1', { imageBase64: png64 });
    }
    expect((await err(uploadImage(deps(), 'u1', { imageBase64: png64 })))?.code).toBe('resource-exhausted');
    await uploadImage(deps(), 'u2', { imageBase64: png64 }); // other users unaffected
    clock += 3_600_000;
    await uploadImage(deps(), 'u1', { imageBase64: png64 });
  });
});
