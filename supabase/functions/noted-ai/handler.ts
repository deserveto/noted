import { fetchAllPages } from '../_shared/pagination.ts';
import { requireAuthenticatedUser, type VerifyBearerToken } from '../_shared/auth.ts';
import {
  AppError,
  errorResponse,
  handleCorsPreflight,
  jsonResponse,
} from '../_shared/cors.ts';
import {
  plainTextFromContent,
  rankNotesForPrompt,
  scopedNotes,
  validatedAnswer,
  type ScopedNoteRecord,
} from '../_shared/policy.ts';

export interface NotedAiStore {
  checkRateLimit(uid: string, op: string, limit: number): Promise<boolean>;
  getSettings(uid: string): Promise<Record<string, unknown>>;
  getAiRequest(uid: string, requestId: string): Promise<{ cancelled: boolean; status: string } | null>;
  upsertAiRequest(uid: string, requestId: string, patch: Record<string, unknown>): Promise<void>;
  clearHistory(uid: string): Promise<void>;
  listAccessibleNotes(uid: string): Promise<ScopedNoteRecord[]>;
  listRecentChatMessages(
    uid: string,
    chatId: string,
    limit: number,
  ): Promise<Array<{ role: string; text?: string; blocks?: unknown[]; sources?: string[]; context_dependencies?: string[] | null }>>;
  commitAiExchange(params: {
    uid: string;
    requestId: string;
    chatId: string;
    title: string;
    scope: Record<string, unknown>;
    prompt: string;
    answer: { blocks: Record<string, unknown>[]; sources: string[]; intent: string };
    contextDependencies: string[];
    persist: boolean;
  }): Promise<string | null>;
}

export interface NotedAiDeps {
  verifyToken: VerifyBearerToken;
  store: NotedAiStore;
  fetchImpl?: typeof fetch;
  env: {
    aiBaseUrl?: string;
    aiModel?: string;
    aiApiKey?: string;
    appUrl?: string;
  };
}

function extractJsonObject(rawContent: string): Record<string, unknown> {
  const trimmed = String(rawContent ?? '').trim();
  const unfenced = trimmed
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim();
  try {
    const parsed = JSON.parse(unfenced);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    const start = unfenced.indexOf('{');
    const end = unfenced.lastIndexOf('}');
    if (start >= 0 && end > start) {
      const sliced = JSON.parse(unfenced.slice(start, end + 1));
      if (sliced && typeof sliced === 'object' && !Array.isArray(sliced)) {
        return sliced as Record<string, unknown>;
      }
    }
  }
  throw new AppError('unavailable', 'AI returned invalid JSON.');
}

async function callOpenAiCompatibleProvider(params: {
  fetchFn: typeof fetch;
  baseUrl: string;
  apiKey: string;
  model: string;
  appUrl?: string;
  messages: Array<{ role: string; content: string }>;
  signal: AbortSignal;
}): Promise<Record<string, unknown>> {
  const endpoint = `${params.baseUrl.replace(/\/+$/, '')}/chat/completions`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${params.apiKey}`,
    'Content-Type': 'application/json',
  };
  if (params.baseUrl.includes('openrouter.ai')) {
    headers['HTTP-Referer'] = params.appUrl?.startsWith('https://')
      ? params.appUrl
      : 'https://noted.app';
    headers['X-Title'] = 'Noted';
  }

  const send = (withJsonFormat: boolean) =>
    params.fetchFn(endpoint, {
      method: 'POST',
      headers,
      signal: params.signal,
      body: JSON.stringify({
        model: params.model,
        temperature: 0.3,
        messages: params.messages,
        ...(withJsonFormat ? { response_format: { type: 'json_object' } } : {}),
      }),
    });

  let res = await send(true);
  if (res.status === 400 || res.status === 422) {
    res = await send(false);
  }
  if (!res.ok) {
    throw new AppError(
      'unavailable',
      `AI provider returned status ${res.status}.`,
    );
  }

  const body = (await res.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const content = body?.choices?.[0]?.message?.content ?? '{}';
  return extractJsonObject(content);
}

export function createSupabaseNotedAiStore(admin: any): NotedAiStore {
  return {
    async checkRateLimit(uid, op, limit) {
      const { data, error } = await admin.rpc('check_rate_limit', {
        p_user_id: uid,
        p_operation: op,
        p_limit: limit,
        p_window_seconds: 3600,
      });
      if (error) throw new AppError('internal', error.message);
      return Boolean(data);
    },
    async getSettings(uid) {
      const { data } = await admin
        .from('user_settings')
        .select('preferences')
        .eq('user_id', uid)
        .maybeSingle();
      return (data?.preferences ?? {}) as Record<string, unknown>;
    },
    async getAiRequest(uid, requestId) {
      const { data, error } = await admin
        .from('ai_requests')
        .select('cancelled, status')
        .eq('user_id', uid)
        .eq('request_id', requestId)
        .maybeSingle();
      if (error) throw new AppError('internal', 'Could not read AI request.');
      return data ?? null;
    },
    async upsertAiRequest(uid, requestId, patch) {
      if (patch.cancelled === false) {
        const { error } = await admin.from('ai_requests').upsert(
          {
            user_id: uid,
            request_id: requestId,
            updated_at: new Date().toISOString(),
            ...patch,
          },
          { onConflict: 'user_id,request_id', ignoreDuplicates: true },
        );
        if (error) throw new AppError('internal', 'Could not update AI request.');
        return;
      }
      const { error } = await admin.from('ai_requests').upsert(
        {
          user_id: uid,
          request_id: requestId,
          updated_at: new Date().toISOString(),
          ...patch,
        },
        { onConflict: 'user_id,request_id' },
      );
      if (error) throw new AppError('internal', 'Could not update AI request.');
    },
    async clearHistory(uid) {
      const { error } = await admin.rpc('audit_clear_ai_history', { p_user_id: uid });
      if (error) throw new AppError('internal', 'Could not clear AI history.');
    },
    async listAccessibleNotes(uid) {
      const [owned, live, favs] = await Promise.all([
        fetchAllPages(() => admin.from('notes').select('*').eq('user_id', uid).is('deleted_at', null), 'note_id'),
        fetchAllPages(() => admin.from('notes').select('*').contains('live_member_ids', [uid]).is('deleted_at', null), 'note_id'),
        fetchAllPages(() => admin.from('user_favorites').select('note_id').eq('user_id', uid), 'note_id'),
      ]);
      const favIds = new Set((favs ?? []).map((f: any) => String(f.note_id)));
      const merged = new Map<string, ScopedNoteRecord>();
      for (const row of [...(owned ?? []), ...(live ?? [])]) {
        const id = String(row.note_id);
        merged.set(id, {
          id,
          title: row.title ?? '',
          content: row.content ?? '',
          category: row.category ?? 'Personal',
          color: row.color ?? 'blue',
          isFavorite:
            row.user_id === uid ? Boolean(row.is_favorite) : favIds.has(id),
          createdAt: row.created_at,
          updatedAt: row.updated_at,
        });
      }
      return [...merged.values()];
    },
    async listRecentChatMessages(uid, chatId, limit) {
      const { data } = await admin
        .from('ai_messages')
        .select('role, text, blocks, sources, context_dependencies')
        .eq('user_id', uid)
        .eq('chat_id', chatId)
        .order('created_at', { ascending: false })
        .limit(limit);
      return ((data ?? []) as any[]).reverse();
    },
    async commitAiExchange({ uid, requestId, chatId, title, scope, prompt, answer, contextDependencies, persist }) {
      const { data, error } = await admin.rpc('audit_commit_ai_exchange', {
        p_user_id: uid, p_request_id: requestId, p_dependencies: contextDependencies, p_chat_id: chatId,
        p_title: title, p_scope: scope, p_prompt: prompt, p_answer: answer, p_persist: persist,
      });
      if (error) {
        if (error.code === '57014') throw new AppError('cancelled', 'AI request was stopped.');
        if (error.code === '42501') throw new AppError('permission-denied', 'Access to a supplied note changed while generating the answer.');
        throw new AppError('internal', 'Could not commit the AI answer.');
      }
      if (!data || !('messageId' in data)) throw new AppError('internal', 'Invalid AI commit result.');
      return data.messageId ?? null;
    },
  };
}

export async function handleNotedAiRequest(
  req: Request,
  deps: NotedAiDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    const caller = await requireAuthenticatedUser(req, deps.verifyToken);
    const payload = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const action = String(payload.action ?? 'ask');

    if (action === 'cancel') {
      const requestId = String(payload.requestId ?? '').trim();
      if (!requestId || requestId.length > 80) {
        throw new AppError('invalid-argument', 'Valid request ID is required.');
      }
      await deps.store.upsertAiRequest(caller.uid, requestId, {
        cancelled: true,
        status: 'cancelled',
      });
      return jsonResponse({ ok: true });
    }

    if (action === 'clearHistory') {
      await deps.store.clearHistory(caller.uid);
      return jsonResponse({ ok: true });
    }

    if (action !== 'ask') {
      throw new AppError('invalid-argument', `Unsupported AI action: ${action}`);
    }

    const prompt = String(payload.prompt ?? '').trim();
    if (!prompt || prompt.length > 12000) {
      throw new AppError('invalid-argument', 'Enter a shorter question.');
    }

    const settings = await deps.store.getSettings(caller.uid);
    if (settings.aiEnabled === false) {
      throw new AppError(
        'failed-precondition',
        'Noted AI is turned off in Settings.',
      );
    }

    const apiKey = deps.env.aiApiKey?.trim() ?? '';
    if (!apiKey) {
      throw new AppError(
        'failed-precondition',
        'AI provider is not configured yet.',
      );
    }

    const allowed = await deps.store.checkRateLimit(caller.uid, 'ai', 40);
    if (!allowed) {
      throw new AppError(
        'resource-exhausted',
        'Too many AI requests. Try again shortly.',
      );
    }

    const requestId = payload.requestId
      ? String(payload.requestId).slice(0, 80)
      : crypto.randomUUID().replace(/-/g, '');

    const existingReq = await deps.store.getAiRequest(caller.uid, requestId);
    if (existingReq?.cancelled) {
      throw new AppError('cancelled', 'AI request was stopped.');
    }
    await deps.store.upsertAiRequest(caller.uid, requestId, {
      cancelled: false,
      status: 'running',
    });
    const afterStartReq = await deps.store.getAiRequest(caller.uid, requestId);
    if (afterStartReq?.cancelled) {
      throw new AppError('cancelled', 'AI request was stopped.');
    }

    const baseUrl = deps.env.aiBaseUrl?.trim() || 'https://openrouter.ai/api/v1';
    const model = deps.env.aiModel?.trim() || 'openrouter/free';

    const all = await deps.store.listAccessibleNotes(caller.uid);
    const allowedIds = new Set(all.map((n) => String(n.id)));
    const scope =
      payload.scope && typeof payload.scope === 'object'
        ? (payload.scope as Record<string, unknown>)
        : { kind: 'all' };

    const candidates = scopedNotes(all, scope);
    const ranked = rankNotesForPrompt(candidates, prompt, 8);
    const contextIds = new Set(ranked.map((n) => String(n.id)));
    const selection =
      typeof payload.selection === 'string'
        ? payload.selection.slice(0, 12000)
        : '';

    if (selection) {
      const selectedId = String(payload.selectionNoteId ?? '').trim();
      const selectedNote = all.find((note) => String(note.id) === selectedId);
      const selectedText = selection.replace(/\s+/g, ' ').trim();
      const sourceText = selectedNote ? plainTextFromContent(selectedNote.content) : '';
      if (!selectedId || !selectedNote || !selectedText ||
          !sourceText.includes(selectedText)) {
        throw new AppError('permission-denied', 'Selected text must belong to an accessible saved note.');
      }
      contextIds.add(selectedId);
    }

    const chatId = payload.chatId
      ? String(payload.chatId).slice(0, 80)
      : crypto.randomUUID().replace(/-/g, '');

    const history: Array<{ role: string; content: string }> = [];
    if (payload.chatId && settings.aiHistory !== false) {
      const prior = await deps.store.listRecentChatMessages(caller.uid, chatId, 8);
      for (const m of prior) {
        if (!Array.isArray(m.context_dependencies) ||
            m.context_dependencies.some((id) => !allowedIds.has(String(id)))) continue;
        const text =
          m.role === 'user'
            ? String(m.text ?? '')
            : Array.isArray(m.blocks)
              ? m.blocks
                  .map((b: any) => b?.x || (Array.isArray(b?.items) ? b.items.join(' ') : ''))
                  .join('\n')
              : '';
        if (text) {
          for (const id of m.context_dependencies) contextIds.add(String(id));
          history.push({
            role: m.role === 'user' ? 'user' : 'assistant',
            content: text.slice(0, 3000),
          });
        }
      }
    }

    const aiLength = String(settings.aiLength ?? 'balanced').toLowerCase();
    const lengthInstruction =
      aiLength === 'concise'
        ? 'Keep responses brief and concise (2-4 short points or sentences).'
        : aiLength === 'detailed'
          ? 'Provide thorough, well-structured detail covering nuances from the notes.'
          : 'Use balanced length: clear, focused, and appropriately detailed.';

    const aiTone = String(settings.aiTone ?? 'direct').toLowerCase();
    const toneInstruction =
      aiTone === 'friendly'
        ? 'Use a warm, encouraging, conversational tone.'
        : aiTone === 'academic'
          ? 'Use a precise, analytical, academic tone.'
          : 'Keep prose clear, direct, and grounded.';

    const requestedIntent =
      typeof payload.intent === 'string' && payload.intent.trim()
        ? `Preferred output intent: ${payload.intent.trim().slice(0, 40)}.`
        : '';

    const systemPrompt = [
      'You are Noted AI, a calm editorial assistant inside a personal and business notes app.',
      'Use ONLY the supplied notes and selected text. Never invent sources or cite note IDs not supplied.',
      'Return strict JSON only: {"intent":"summary|actions|rewrite|flashcards|answer","blocks":[...],"sources":["noteId"]}.',
      'Allowed block shapes: {"t":"h","x":"Heading"}, {"t":"p","x":"Paragraph"}, {"t":"quote","x":"Excerpt"}, {"t":"ul","items":["Item"]}, {"t":"ol","items":["Step"]}, {"t":"todo","items":[{"x":"Task","done":false}]}, {"t":"cards","items":[{"q":"Question","a":"Answer"}]}.',
      lengthInstruction,
      toneInstruction,
      requestedIntent,
    ]
      .filter(Boolean)
      .join(' ');

    const noteContext = ranked.map((n) => ({
      id: n.id,
      title: n.title || 'Untitled',
      category: n.category || 'Personal',
      text: plainTextFromContent(n.content).slice(0, 16000),
    }));

    const abortController = new AbortController();
    const cancelPoll = setInterval(async () => {
      try {
        const latest = await deps.store.getAiRequest(caller.uid, requestId);
        if (latest?.cancelled) abortController.abort();
      } catch {
        // Ignore transient poll errors
      }
    }, 500);

    let rawJson: Record<string, unknown>;
    try {
      rawJson = await callOpenAiCompatibleProvider({
        fetchFn: deps.fetchImpl ?? fetch,
        baseUrl,
        apiKey,
        model,
        appUrl: deps.env.appUrl,
        signal: abortController.signal,
        messages: [
          { role: 'system', content: systemPrompt },
          ...history,
          {
            role: 'user',
            content: JSON.stringify({
              question: prompt,
              selectedText: selection || undefined,
              notes: noteContext,
            }),
          },
        ],
      });
    } catch (err) {
      const latest = await deps.store.getAiRequest(caller.uid, requestId);
      if (abortController.signal.aborted || latest?.cancelled) {
        await deps.store.upsertAiRequest(caller.uid, requestId, {
          cancelled: true,
          status: 'cancelled',
        });
        throw new AppError('cancelled', 'AI request was stopped.');
      }
      await deps.store.upsertAiRequest(caller.uid, requestId, {
        cancelled: false,
        status: 'failed',
        completed_at: new Date().toISOString(),
      });
      if (err instanceof AppError) throw err;
      throw new AppError('unavailable', 'Could not reach AI provider.');
    } finally {
      clearInterval(cancelPoll);
    }

    const validated = validatedAnswer(rawJson, contextIds);

    // Re-check cancellation and note access right before persisting
    const [latestReq, currentNotes] = await Promise.all([
      deps.store.getAiRequest(caller.uid, requestId),
      deps.store.listAccessibleNotes(caller.uid),
    ]);
    if (latestReq?.cancelled) {
      throw new AppError('cancelled', 'AI request was stopped.');
    }

    const stillAllowed = new Set(currentNotes.map((n) => String(n.id)));
    if ([...contextIds].some((id) => !stillAllowed.has(id))) {
      throw new AppError('permission-denied', 'Access to a supplied note changed while generating the answer.');
    }
    const finalAnswer = validated;

    const messageId = await deps.store.commitAiExchange({
      uid: caller.uid,
      requestId,
      chatId,
      title: prompt.slice(0, 72),
      scope,
      prompt,
      answer: finalAnswer,
      contextDependencies: [...contextIds],
      persist: settings.aiHistory !== false,
    });


    return jsonResponse({
      ...finalAnswer,
      chatId,
      messageId,
      requestId,
    });
  } catch (err) {
    return errorResponse(err);
  }
}
