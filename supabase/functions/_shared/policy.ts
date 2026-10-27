import { AppError } from './cors.ts';

export const VALID_COLORS = new Set([
  'blue',
  'pink',
  'mint',
  'yellow',
  'peach',
  'lav',
]);

export function isValidUuid(value: unknown): boolean {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value.trim(),
    )
  );
}

export function isValidEmailAddress(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 320 || /[%_\s]/.test(trimmed.split('@')[1] ?? '')) {
    return false;
  }
  if (trimmed.includes('%')) return false;
  return /^[^\s@%]+@[^\s@%_]+\.[^\s@%_]+$/.test(trimmed);
}

export function escapeHtml(input: unknown): string {
  return String(input ?? '').replace(
    /[&<>"']/g,
    (ch) =>
      (({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      }) as Record<string, string>)[ch] ?? ch,
  );
}

export function plainTextFromContent(raw: unknown): string {
  const s = String(raw ?? '');
  const trimmed = s.trimLeft();
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === 'object' && Array.isArray(parsed.ops)) {
        return parsed.ops
          .map((op: Record<string, unknown>) =>
            typeof op?.insert === 'string' ? op.insert : ' ',
          )
          .join('')
          .replace(/\s+/g, ' ')
          .trim();
      }
    } catch {
      // Fall through to legacy text cleanup
    }
  }
  return s
    .replace(/<[^>]+>/g, ' ')
    .replace(/[*_`~>#-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function htmlFromContent(raw: unknown): string {
  const s = String(raw ?? '');
  const trimmed = s.trimLeft();
  if (trimmed.startsWith('<')) return s;
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === 'object' && Array.isArray(parsed.ops)) {
        const text = parsed.ops
          .map((op: Record<string, unknown>) => {
            if (typeof op?.insert !== 'string') return '';
            let chunk = escapeHtml(op.insert);
            const attrs = (op.attributes ?? {}) as Record<string, unknown>;
            if (attrs.bold) chunk = `<strong>${chunk}</strong>`;
            if (attrs.italic) chunk = `<em>${chunk}</em>`;
            if (attrs.underline) chunk = `<u>${chunk}</u>`;
            return chunk;
          })
          .join('');
        return `<p>${text.replace(/\n/g, '<br/>')}</p>`;
      }
    } catch {
      // Fall through
    }
  }
  return `<p>${escapeHtml(s).replace(/\n/g, '<br/>')}</p>`;
}

export interface AttachmentMeta {
  type: string;
  name: string;
  path?: string;
  url: string;
  duration?: number;
}

export interface DraftCopy {
  title: string;
  content: string;
  category: string;
  color: string;
  attachments: AttachmentMeta[];
}

export function draftForCopy(input: Record<string, unknown> = {}): DraftCopy {
  const title = typeof input.title === 'string' ? input.title : '';
  const content = typeof input.content === 'string' ? input.content : '';
  const category =
    typeof input.category === 'string' && input.category.trim()
      ? input.category.trim()
      : 'Personal';
  const color =
    typeof input.color === 'string' && VALID_COLORS.has(input.color)
      ? input.color
      : 'blue';
  const rawAttachments = Array.isArray(input.attachments)
    ? input.attachments
    : [];

  if (
    title.length > 1000 ||
    content.length > 800000 ||
    category.length > 200 ||
    rawAttachments.length > 100
  ) {
    throw new AppError('invalid-argument', 'Draft is too large.');
  }

  const attachments: AttachmentMeta[] = rawAttachments
    .filter((a): a is Record<string, unknown> => Boolean(a) && typeof a === 'object')
    .map((a) => ({
      type: String(a.type ?? 'image'),
      name: String(a.name ?? 'file').slice(0, 160),
      ...(typeof a.path === 'string' && a.path.length <= 500
        ? { path: a.path }
        : {}),
      url: typeof a.url === 'string' ? a.url.slice(0, 2000) : '',
      ...(typeof a.duration === 'number' ? { duration: a.duration } : {}),
    }))
    .filter((a) => Boolean(a.url) || Boolean(a.path));

  return { title, content, category, color, attachments };
}

export interface ScopedNoteRecord {
  id: string;
  title?: string;
  content?: string;
  category?: string;
  color?: string;
  isFavorite?: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export function scopedNotes<T extends ScopedNoteRecord>(
  all: T[],
  scope: Record<string, unknown> = {},
): T[] {
  const kind = scope?.kind ?? 'all';
  if (kind === 'fav') return all.filter((n) => Boolean(n.isFavorite));
  if (kind === 'cat') return all.filter((n) => n.category === scope.cat);
  if (kind === 'notes') {
    const rawIds = Array.isArray(scope.ids) ? scope.ids : [];
    const ids = new Set(rawIds.slice(0, 100).map(String));
    return all.filter((n) => ids.has(String(n.id)));
  }
  return all;
}

export function rankNotesForPrompt<T extends ScopedNoteRecord>(
  candidates: T[],
  prompt: string,
  limit = 8,
): T[] {
  const terms = String(prompt ?? '')
    .toLowerCase()
    .split(/\W+/)
    .filter((t) => t.length > 2);

  return [...candidates]
    .sort((a, b) => {
      const score = (n: T) => {
        const hay = `${n.title ?? ''} ${plainTextFromContent(n.content)} ${n.category ?? ''}`.toLowerCase();
        return terms.reduce((acc, term) => acc + (hay.includes(term) ? 1 : 0), 0);
      };
      const diff = score(b) - score(a);
      if (diff !== 0) return diff;
      return String(b.updatedAt ?? '').localeCompare(String(a.updatedAt ?? ''));
    })
    .slice(0, limit);
}

const BLOCK_TYPES = new Set([
  'h',
  'p',
  'quote',
  'ul',
  'ol',
  'todo',
  'cards',
]);

export function validatedAnswer(
  raw: Record<string, unknown> | null | undefined,
  allowedIds: Set<string>,
): { blocks: Record<string, unknown>[]; sources: string[]; intent: string } {
  const rawBlocks = Array.isArray(raw?.blocks) ? raw!.blocks.slice(0, 24) : [];
  const blocks: Record<string, unknown>[] = [];

  for (const b of rawBlocks) {
    if (!b || typeof b !== 'object') continue;
    const item = b as Record<string, unknown>;
    const t = String(item.t ?? '');
    if (!BLOCK_TYPES.has(t)) continue;

    if (t === 'h' || t === 'p' || t === 'quote') {
      const x = String(item.x ?? '').trim().slice(0, 4000);
      if (x) blocks.push({ t, x });
    } else if (t === 'ul' || t === 'ol') {
      const items = (Array.isArray(item.items) ? item.items : [])
        .map((v) => String(v ?? '').trim().slice(0, 600))
        .filter(Boolean)
        .slice(0, 20);
      if (items.length) blocks.push({ t, items });
    } else if (t === 'todo') {
      const items = (Array.isArray(item.items) ? item.items : [])
        .map((v) =>
          typeof v === 'string'
            ? { x: v.trim().slice(0, 600), done: false }
            : {
                x: String((v as Record<string, unknown>)?.x ?? '')
                  .trim()
                  .slice(0, 600),
                done: Boolean((v as Record<string, unknown>)?.done),
              },
        )
        .filter((v) => v.x)
        .slice(0, 20);
      if (items.length) blocks.push({ t, items });
    } else if (t === 'cards') {
      const items = (Array.isArray(item.items) ? item.items : [])
        .map((v) => {
          const obj = (v ?? {}) as Record<string, unknown>;
          return {
            q: String(obj.q ?? '').trim().slice(0, 400),
            a: String(obj.a ?? '').trim().slice(0, 800),
          };
        })
        .filter((v) => v.q && v.a)
        .slice(0, 20);
      if (items.length) blocks.push({ t, items });
    }
  }

  if (!blocks.length) {
    throw new AppError('unavailable', 'AI returned an unreadable response.');
  }

  const rawSources = Array.isArray(raw?.sources) ? raw!.sources : [];
  const sources = [
    ...new Set(
      rawSources
        .map(String)
        .filter((id) => allowedIds.has(id)),
    ),
  ].slice(0, 20);

  const intent =
    typeof raw?.intent === 'string' ? raw.intent.slice(0, 40) : 'answer';

  return { blocks, sources, intent };
}

export function emailAllowed(
  settings: Record<string, unknown> = {},
  timezoneOffsetMinutes = 0,
  now: Date = new Date(),
): boolean {
  if (settings.quietHours === false) return true;
  const offset =
    typeof timezoneOffsetMinutes === 'number'
      ? timezoneOffsetMinutes
      : typeof settings.timezoneOffsetMinutes === 'number'
        ? settings.timezoneOffsetMinutes
        : 0;
  const local = new Date(now.getTime() + offset * 60000);
  const hour = local.getUTCHours();
  return hour >= 7 && hour < 22;
}

export function exportNotes(
  notes: ScopedNoteRecord[],
  exportedAt: string = new Date().toISOString(),
) {
  return {
    formatVersion: 1,
    exportedAt,
    notes: notes.map((n) => ({
      noteId: n.id,
      title: n.title ?? '',
      category: n.category ?? 'Personal',
      color: VALID_COLORS.has(String(n.color)) ? n.color : 'blue',
      isFavorite: Boolean(n.isFavorite),
      createdAt: n.createdAt ?? exportedAt,
      updatedAt: n.updatedAt ?? exportedAt,
      content: n.content ?? '',
      html: htmlFromContent(n.content),
      plainText: plainTextFromContent(n.content),
    })),
  };
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export async function deterministicPairId(
  uidA: string,
  uidB: string,
): Promise<string> {
  return sha256Hex([uidA, uidB].sort().join('_'));
}
