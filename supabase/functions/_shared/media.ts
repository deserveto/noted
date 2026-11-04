import { AppError } from './cors.ts';
import type { AttachmentMeta } from './policy.ts';

export const NOTE_MEDIA_BUCKET = 'note-media';
export const AVATARS_BUCKET = 'avatars';

export interface StorageBucketAdmin {
  copy(fromPath: string, toPath: string): Promise<{ error: { message: string } | null }>;
  remove(paths: string[]): Promise<{ error: { message: string } | null }>;
  list?(
    prefix?: string,
    options?: { limit?: number; offset?: number },
  ): Promise<{
    data: Array<{ name: string; id?: string | null; metadata?: Record<string, unknown> | null }> | null;
    error: { message: string } | null;
  }>;
}

export interface StorageAdmin {
  from(bucket: string): StorageBucketAdmin;
}

export function canonicalMediaUri(bucket: string, path: string): string {
  return `noted-media://${bucket}/${path.replace(/^\/+/, '')}`;
}

export function isValidNoteAttachmentPath(path: string, noteId: string): boolean {
  const parts = path.replace(/^\/+/, '').split('/');
  return (
    parts.length === 5 &&
    parts[0] === 'users' &&
    Boolean(parts[1]) &&
    parts[2] === 'notes' &&
    parts[3] === noteId &&
    Boolean(parts[4]) &&
    !parts.includes('..')
  );
}

function replaceAllLiterals(text: string, from: string, to: string): string {
  if (!from || from === to) return text;
  let result = text.split(from).join(to);
  const jsonFrom = JSON.stringify(from).slice(1, -1);
  const jsonTo = JSON.stringify(to).slice(1, -1);
  if (jsonFrom !== from) {
    result = result.split(jsonFrom).join(jsonTo);
  }
  return result;
}

/**
 * Copies every private attachment belonging to `sourceNoteId` into an independent
 * storage prefix `users/<targetUserId>/notes/<targetNoteId>/<uuid>_<safeName>` in
 * the private `note-media` bucket, rewriting inline references and rolling back
 * any copied objects if a failure occurs partway through.
 */
const MAX_COPY_ATTACHMENTS = 100;
const MAX_COPY_INLINE_MEDIA = 200;

function noteMediaPathFromReference(reference: string): string {
  const prefix = `noted-media://${NOTE_MEDIA_BUCKET}/`;
  if (!reference.startsWith(prefix)) return '';
  return reference.slice(prefix.length).replace(/^\/+/, '');
}

function inlineMediaPaths(content: string, sourceNoteId: string): string[] {
  const found = new Set<string>();
  const pattern = new RegExp(
    `noted-media://${NOTE_MEDIA_BUCKET}/([^"'\\\\\\s)]+)`,
    'g',
  );
  for (const match of content.matchAll(pattern)) {
    const path = match[1].replace(/^\/+/, '');
    if (!isValidNoteAttachmentPath(path, sourceNoteId)) {
      throw new AppError(
        'permission-denied',
        'Inline media does not belong to the source note.',
      );
    }
    found.add(path);
  }
  return [...found];
}

/**
 * Copies every private attachment and inline image belonging to `sourceNoteId`
 * into an independent storage prefix `users/<targetUserId>/notes/<targetNoteId>/...`
 * in the private `note-media` bucket. Both `attachments` metadata and inline
 * `noted-media://` references inside `content` are rewritten, duplicate paths
 * are copied once, and copied objects are rolled back on failure.
 */
export async function copyAttachmentsForNote(params: {
  storage: StorageAdmin;
  sourceNoteId: string;
  targetUserId: string;
  targetNoteId: string;
  content: string;
  attachments: AttachmentMeta[];
}): Promise<{ content: string; attachments: AttachmentMeta[] }> {
  const {
    storage,
    sourceNoteId,
    targetUserId,
    targetNoteId,
  } = params;
  let nextContent = String(params.content ?? '');
  const inputAttachments = (Array.isArray(params.attachments)
    ? params.attachments
    : [])
    .filter((raw) => raw && typeof raw === 'object')
    .slice(0, MAX_COPY_ATTACHMENTS);

  const nameByPath = new Map<string, string>();
  const orderedPaths: string[] = [];
  const addPath = (path: string, name?: string) => {
    if (!path) return;
    if (!isValidNoteAttachmentPath(path, sourceNoteId)) {
      throw new AppError(
        'permission-denied',
        'Attachment path does not belong to the source note.',
      );
    }
    if (!nameByPath.has(path)) {
      nameByPath.set(path, name ?? path.split('/').pop() ?? 'file');
      orderedPaths.push(path);
    } else if (name) {
      nameByPath.set(path, name);
    }
  };

  for (const raw of inputAttachments) {
    const explicitPath =
      typeof raw.path === 'string' ? raw.path.trim().replace(/^\/+/, '') : '';
    const path = explicitPath ||
      (typeof raw.url === 'string' ? noteMediaPathFromReference(raw.url) : '');
    if (path) addPath(path, typeof raw.name === 'string' ? raw.name : undefined);
  }
  for (const path of inlineMediaPaths(nextContent, sourceNoteId)) {
    addPath(path);
  }

  if (orderedPaths.length === 0) {
    return { content: nextContent, attachments: inputAttachments.map((raw) => ({ ...raw })) };
  }
  if (orderedPaths.length > MAX_COPY_INLINE_MEDIA) {
    throw new AppError('resource-exhausted', 'This note has too many images to copy.');
  }

  const bucket = storage.from(NOTE_MEDIA_BUCKET);
  const copiedPaths: string[] = [];
  const copiedBySource = new Map<string, { path: string; canonical: string }>();

  try {
    for (const oldPath of orderedPaths) {
      const safeName =
        String(nameByPath.get(oldPath) || oldPath.split('/').pop() || 'file')
          .replace(/[^a-zA-Z0-9._-]/g, '_')
          .slice(0, 80) || 'file';
      const newPath = `users/${targetUserId}/notes/${targetNoteId}/${crypto.randomUUID()}_${safeName}`;

      const { error } = await bucket.copy(oldPath, newPath);
      if (error) {
        throw new AppError(
          'failed-precondition',
          `Attachment could not be copied: ${error.message}`,
        );
      }
      copiedPaths.push(newPath);
      copiedBySource.set(oldPath, {
        path: newPath,
        canonical: canonicalMediaUri(NOTE_MEDIA_BUCKET, newPath),
      });
    }

    for (const [oldPath, copied] of copiedBySource) {
      const oldCanonical = canonicalMediaUri(NOTE_MEDIA_BUCKET, oldPath);
      nextContent = replaceAllLiterals(nextContent, oldCanonical, copied.canonical);
    }

    const nextAttachments: AttachmentMeta[] = inputAttachments.map((raw) => {
      const explicitPath =
        typeof raw.path === 'string' ? raw.path.trim().replace(/^\/+/, '') : '';
      const oldPath = explicitPath ||
        (typeof raw.url === 'string' ? noteMediaPathFromReference(raw.url) : '');
      const copied = oldPath ? copiedBySource.get(oldPath) : undefined;
      if (!copied) return { ...raw };
      return { ...raw, path: copied.path, url: copied.canonical };
    });

    return { content: nextContent, attachments: nextAttachments };
  } catch (err) {
    if (copiedPaths.length > 0) {
      await Promise.resolve(bucket.remove(copiedPaths)).catch(() => undefined);
    }
    if (err instanceof AppError) throw err;
    throw new AppError('failed-precondition', 'Attachment could not be copied.');
  }
}

export async function deleteStoragePrefixRecursively(
  storage: StorageAdmin,
  bucketName: string,
  prefix: string,
  maxDepth = 5,
): Promise<number> {
  if (maxDepth <= 0) throw new AppError('internal', 'Storage folder depth exceeded.');
  const bucket = storage.from(bucketName);
  if (!bucket.list) throw new AppError('internal', 'Storage listing unavailable.');

  const cleanPrefix = prefix.replace(/^\/+|\/+$/g, '');
  let deleted = 0;
  const pageSize = 500;

  while (true) {
    const { data, error } = await bucket.list(cleanPrefix, { limit: pageSize, offset: 0 });
    if (error || !data) throw new AppError('internal', `Storage listing failed: ${error?.message ?? 'missing data'}`);
    if (data.length === 0) break;

    const before = deleted;
    const filePaths: string[] = [];
    for (const item of data) {
      if (!item?.name) continue;
      const fullPath = cleanPrefix ? `${cleanPrefix}/${item.name}` : item.name;
      const isFolder =
        ('id' in item || 'metadata' in item) &&
        item.id === null &&
        !item.metadata;
      if (isFolder) {
        deleted += await deleteStoragePrefixRecursively(
          storage,
          bucketName,
          fullPath,
          maxDepth - 1,
        );
      } else {
        filePaths.push(fullPath);
      }
    }

    if (filePaths.length > 0) {
      const { error: removeError } = await bucket.remove(filePaths);
      if (removeError) throw new AppError('internal', `Storage deletion failed: ${removeError.message}`);
      deleted += filePaths.length;
    }

    if (data.length < pageSize) break;
    if (deleted === before) throw new AppError('internal', 'Storage cleanup made no progress.');
    // Folder entries are virtual and disappear after their contents are removed.
    // Re-list from the beginning because deletion shifts the next page left.
  }

  return deleted;
}

export async function deleteNoteMediaObjects(params: {
  storage: StorageAdmin;
  noteId: string;
  ownerUserId?: string;
  attachments: unknown;
}): Promise<number> {
  const list = Array.isArray(params.attachments) ? params.attachments : [];
  const pathSet = new Set<string>(
    list
      .map((a) =>
        a && typeof a === 'object' && typeof (a as Record<string, unknown>).path === 'string'
          ? String((a as Record<string, unknown>).path).replace(/^\/+/, '')
          : '',
      )
      .filter((p) => p && isValidNoteAttachmentPath(p, params.noteId)),
  );

  const bucket = params.storage.from(NOTE_MEDIA_BUCKET);
  let deleted = 0;
  const paths = [...pathSet];
  if (paths.length) {
    const { error } = await bucket.remove(paths);
    if (error) throw new AppError('internal', `Storage deletion failed: ${error.message}`);
    deleted += paths.length;
  }
  if (params.ownerUserId) {
    if (!params.noteId || params.noteId.includes('/') || params.noteId === '.' || params.noteId === '..') {
      throw new AppError('invalid-argument', 'Invalid note storage prefix.');
    }
    if (!bucket.list) throw new AppError('internal', 'Storage listing unavailable.');
    // Discover every uploader before removing anything, so deleting a user's
    // last object cannot shift the next page and hide another uploader.
    const users = new Set<string>([params.ownerUserId]);
    const size = 500;
    for (let offset = 0; ; offset += size) {
      const { data, error } = await bucket.list('users', { limit: size, offset });
      if (error || !data) throw new AppError('internal', `Storage listing failed: ${error?.message ?? 'missing data'}`);
      for (const item of data) {
        if (item?.name && item.id === null && !item.metadata && !item.name.includes('/')) users.add(item.name);
      }
      if (data.length < size) break;
    }
    for (const uploader of users) {
      deleted += await deleteStoragePrefixRecursively(
        params.storage, NOTE_MEDIA_BUCKET,
        `users/${uploader}/notes/${params.noteId}`,
      );
    }
  }
  return deleted;
}
