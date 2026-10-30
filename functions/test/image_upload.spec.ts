import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { HOURLY_UPLOADS, MAX_IMAGE_BYTES, parseUploadInput, sniffImage, uploadImage, type FetchLike, type UploadDeps } from '../src/image_upload';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32, 1)]);
const png64 = PNG.toString('base64');
const err = async (p: Promise<unknown>) => p.then(() => null, (e) => e as { code: string; message: string });

let calls: { url: string; body: string }[] = [];
let reply: { ok: boolean; status: number; body: string } | 'throw' = { ok: true, status: 200, body: JSON.stringify({ data: { url: 'https://i.ibb.co/abc/pic.png' } }) };
const fetchFn: FetchLike = async (url, init) => {
  calls.push({ url, body: init.body });
  if (reply === 'throw') throw new Error('socket hang up https://api.imgbb.com/1/upload?key=SECRET');
  return { ok: reply.ok, status: reply.status, text: async () => (reply as any).body };
};
let clock = Date.UTC(2026, 9, 31, 4, 0, 0);
const deps = (apiKey = 'k-test'): UploadDeps => ({ db, fetchFn, apiKey, now: () => clock });

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}
beforeAll(clearAll);
beforeEach(async () => {
  await clearAll();
  calls = [];
  reply = { ok: true, status: 200, body: JSON.stringify({ data: { url: 'https://i.ibb.co/abc/pic.png' } }) };
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

describe('uploadImage', () => {
  it('needs a signed-in user and a configured key', async () => {
    expect((await err(uploadImage(deps(), undefined, { imageBase64: png64 })))?.code).toBe('unauthenticated');
    expect((await err(uploadImage(deps(''), 'u1', { imageBase64: png64 })))?.code).toBe('failed-precondition');
    expect(calls).toHaveLength(0);
  });
  it('posts a simple form to imgbb and returns only the URL', async () => {
    const r = await uploadImage(deps(), 'u1', { imageBase64: png64, name: 'pic.png' });
    expect(r).toEqual({ url: 'https://i.ibb.co/abc/pic.png' });
    expect(calls[0].url).toBe('https://api.imgbb.com/1/upload');
    expect(new URLSearchParams(calls[0].body).get('image')).toBe(png64);
    expect(new URLSearchParams(calls[0].body).get('key')).toBe('k-test');
  });
  it('maps host failures to fixed messages and never leaks the key or the host body', async () => {
    reply = { ok: false, status: 400, body: '{"error":{"message":"Invalid API v1 key. key=k-test"}}' };
    const e1 = await err(uploadImage(deps(), 'u1', { imageBase64: png64 }));
    expect(e1?.code).toBe('failed-precondition');
    expect(JSON.stringify(e1)).not.toContain('k-test');
    reply = { ok: false, status: 429, body: '' };
    expect((await err(uploadImage(deps(), 'u1', { imageBase64: png64 })))?.code).toBe('resource-exhausted');
    reply = { ok: false, status: 504, body: '<html>Gateway Time-out</html>' };
    expect((await err(uploadImage(deps(), 'u1', { imageBase64: png64 })))?.code).toBe('unavailable');
    reply = 'throw';
    const e2 = await err(uploadImage(deps(), 'u1', { imageBase64: png64 }));
    expect(e2?.code).toBe('unavailable');
    expect(JSON.stringify(e2)).not.toContain('SECRET');
    reply = { ok: true, status: 200, body: '{"data":{"url":"http://insecure/x.png"}}' };
    expect((await err(uploadImage(deps(), 'u1', { imageBase64: png64 })))?.code).toBe('unavailable');
  });
  it('caps uploads per user per hour and resets the next hour', async () => {
    for (let i = 0; i < HOURLY_UPLOADS; i++) await uploadImage(deps(), 'u1', { imageBase64: png64 });
    expect((await err(uploadImage(deps(), 'u1', { imageBase64: png64 })))?.code).toBe('resource-exhausted');
    await uploadImage(deps(), 'u2', { imageBase64: png64 }); // other users unaffected
    clock += 3_600_000;
    await uploadImage(deps(), 'u1', { imageBase64: png64 });
  });
});
