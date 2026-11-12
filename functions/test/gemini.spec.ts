import { describe, expect, it } from 'vitest';
import { runGeminiAssist } from '../src/gemini';

describe('geminiAssist', () => {
  it('rejects a signed-out caller', async () => {
    await expect(runGeminiAssist(undefined, { action: 'generateCoverNote', jobTitle: 'Painter' }, {
      apiKey: 'k',
      fetchFn: (async () => new Response('{}', { status: 200 })) as typeof fetch,
    })).rejects.toThrow(/Sign in/);
  });

  it('returns the model text and does not put the key in the result', async () => {
    let seen = '';
    const fetchFn = (async (url: string) => {
      seen = url;
      return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'Ready to paint.' }] } }] }), { status: 200 });
    }) as typeof fetch;
    const result = await runGeminiAssist('u1', { action: 'generateCoverNote', jobTitle: 'Painter' }, {
      apiKey: 'DUMMY_GEMINI_KEY',
      fetchFn,
    });
    expect(result).toEqual({ text: 'Ready to paint.' });
    expect(seen).toContain('DUMMY_GEMINI_KEY');
    expect(JSON.stringify(result)).not.toContain('DUMMY_GEMINI_KEY');
  });

  it('returns a category mismatch without calling the model key back to the client', async () => {
    const fetchFn = (async () => new Response(JSON.stringify({
      candidates: [{ content: { parts: [{ text: 'MISMATCH: no' }] } }],
    }), { status: 200 })) as typeof fetch;
    const result = await runGeminiAssist('u1', {
      action: 'generateJobDescription',
      title: 'Plumber',
      categoryLabel: 'Accounting',
    }, { apiKey: 'DUMMY_GEMINI_KEY', fetchFn });
    expect(result).toMatchObject({ mismatch: true, title: 'Plumber', categoryLabel: 'Accounting' });
    expect(JSON.stringify(result)).not.toContain('DUMMY_GEMINI_KEY');
  });
});
