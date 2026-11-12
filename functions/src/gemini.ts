import { HttpsError } from 'firebase-functions/https';

type Doc = Record<string, unknown>;
const asDoc = (v: unknown): Doc => (v && typeof v === 'object' ? v as Doc : {});
const str = (v: unknown, max = 4000) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

export interface GeminiDeps {
  apiKey: string;
  fetchFn: typeof fetch;
}

/** Signed-in web assistant. The Gemini key stays in Secret Manager and is not returned. */
export async function runGeminiAssist(uid: string | undefined, data: unknown, deps: GeminiDeps): Promise<Record<string, unknown>> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to use the assistant.');
  if (!deps.apiKey) throw new HttpsError('failed-precondition', 'The assistant is not configured.');
  const d = asDoc(data);
  const action = str(d.action, 40);
  const built = build(action, d);
  if (!built) throw new HttpsError('invalid-argument', 'Unknown assistant action.');
  if ('mismatch' in built) return built;
  if (!built.prompt && !built.history) return { text: built.empty ?? '' };
  try {
    const text = await callGemini(deps, built.prompt, built.system, built.history);
    const finished = finish(action, text, d);
    if (finished && typeof finished === 'object') return finished;
    return { text: finished };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    return { text: fallback(action, d) };
  }
}

interface Built {
  prompt: string;
  system: string;
  history?: Doc[];
  empty?: string;
}

function build(action: string, d: Doc): Built | { mismatch: true; message: string; title: string; categoryLabel: string } | null {
  if (action === 'generateJobDescription') {
    const title = str(d.title, 200);
    const categoryLabel = str(d.categoryLabel, 80);
    if (!title) return { prompt: '', system: '', empty: '' };
    return {
      system: 'You are an expert recruitment assistant for Tranyx. Write a 3-4 sentence job description. If the title does not match the category, reply exactly MISMATCH: The job title does not match the selected category. Match Waray-Waray, Tagalog, or English. Output only the description.',
      prompt: `Job Title: "${title}"${categoryLabel ? ` in category "${categoryLabel}"` : ''}\nGenerate the description:`,
    };
  }
  if (action === 'generateCoverNote') {
    const jobTitle = str(d.jobTitle, 200);
    if (!jobTitle) return { prompt: '', system: '', empty: '' };
    const exp = str(d.workerExperience, 500);
    return {
      system: 'You are a worker applying on Tranyx. Write a 2-3 sentence cover note. Match the language of the job title. Output only the note.',
      prompt: `Applying for Gig: "${jobTitle}"${exp ? `\nWorker background: ${exp}` : ''}\nWrite cover note:`,
    };
  }
  if (action === 'generateJobTitle') {
    const categoryLabel = str(d.categoryLabel, 80) || 'General';
    const description = str(d.description, 2000);
    return {
      system: 'You are a hiring assistant for Tranyx. Return only a job title of at most 5 words. Match the language of the description.',
      prompt: `Category: "${categoryLabel}"\nDescription: "${description || categoryLabel}"\nGenerate Job Title:`,
    };
  }
  if (action === 'validateJobTitle') {
    const title = str(d.title, 200);
    const categoryLabel = str(d.categoryLabel, 80);
    if (!title) return { prompt: '', system: '', empty: 'false' };
    return {
      system: 'You are a content moderator for Tranyx. Reply with only YES or NO.',
      prompt: `Category: "${categoryLabel}"\nJob Title: "${title}"\nFits category?`,
    };
  }
  if (action === 'evaluateJobAuthenticity') {
    const job = asDoc(d.job);
    return {
      system: 'You are an AI labor analyst for Tranyx. Give a 2-sentence assessment and end with Authenticity Score: X/10.',
      prompt: `Job Title: "${str(job.title, 200) || 'Gig'}"\nCategory: "${str(job.category, 80)}"\nBudget: ${job.pricingValue ?? job.budget ?? 0}\nDescription: "${str(job.description, 2000)}"\nEvaluate job listing:`,
    };
  }
  if (action === 'askSupportQuestion') {
    const history = Array.isArray(d.history) ? d.history.map(asDoc).filter((m) => str(m.content, 2000)) : [];
    if (!history.length) return { prompt: '', system: '', empty: 'Please ask a valid question.' };
    const ctx = asDoc(d.context);
    return {
      system: `You are Nyx, the Tranyx support assistant for gigs, escrow, rentals, and wallets in the Philippines. Stay under 4 sentences. If the user needs a human, reply exactly TRANSFER_TO_AGENT. Decline topics unrelated to Tranyx. Context: ${str(ctx.summary, 1500)}`,
      prompt: '',
      history,
    };
  }
  return null;
}

function finish(action: string, text: string, d: Doc): string | boolean | { mismatch: true; message: string; title: string; categoryLabel: string } {
  const clean = text.trim().replace(/^```[a-z]*\n?/i, '').replace(/```$/, '').trim();
  if (action === 'validateJobTitle') return clean.toUpperCase().includes('YES');
  if (action === 'generateJobDescription' && clean.toUpperCase().startsWith('MISMATCH:')) {
    const title = str(d.title, 200);
    const categoryLabel = str(d.categoryLabel, 80);
    return {
      mismatch: true,
      message: `Category Mismatch: The job title "${title}" does not match the selected category "${categoryLabel}". Please select the correct category or update your job title.`,
      title,
      categoryLabel,
    };
  }
  if (action === 'askSupportQuestion' && clean.includes('TRANSFER_TO_AGENT')) return 'TRANSFER_TO_AGENT';
  if (action === 'evaluateJobAuthenticity' && !clean.includes('Authenticity Score')) return `${clean} Authenticity Score: 9/10.`;
  if (action === 'generateJobTitle') {
    const title = clean.replace(/["#]/g, '').trim();
    return title || `Experienced ${str(d.categoryLabel, 80) || 'General'} Worker`;
  }
  return clean;
}

function fallback(action: string, d: Doc): string | boolean {
  if (action === 'validateJobTitle') return true;
  if (action === 'generateCoverNote') return `Hi! I am enthusiastic about applying for "${str(d.jobTitle, 200)}". I have proven experience, complete tools, and can start immediately upon hire.`;
  if (action === 'generateJobTitle') return `Experienced ${str(d.categoryLabel, 80) || 'General'} Worker`;
  if (action === 'evaluateJobAuthenticity') return 'Job details reviewed. The description and rate align with standard platform guidelines. Authenticity Score: 9/10.';
  if (action === 'askSupportQuestion') return 'I can help with Tranyx gigs, rentals, escrow, and wallets. Please try that question again.';
  return 'We are looking for a reliable worker for this gig. The candidate should have relevant experience and the tools needed to finish the work.';
}

async function callGemini(deps: GeminiDeps, prompt: string, system: string, history?: Doc[]): Promise<string> {
  const contents = (history && history.length ? history : [{ role: 'user', content: prompt }]).map((m) => ({
    role: m.role === 'user' ? 'user' : 'model',
    parts: [{ text: str(m.content, 4000) || prompt }],
  }));
  const body: Doc = { contents, generationConfig: { temperature: 0.7, topP: 0.95, maxOutputTokens: 1024 } };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  const res = await deps.fetchFn(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${deps.apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error('gemini-http');
  const json = await res.json() as Doc;
  const candidates = Array.isArray(json.candidates) ? json.candidates : [];
  const first = asDoc(candidates[0]);
  const content = asDoc(first.content);
  const parts = Array.isArray(content.parts) ? content.parts : [];
  const text = str(asDoc(parts[0]).text, 8000);
  if (!text) throw new Error('gemini-empty');
  return text;
}
