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
  const inputAttachments = Array.isArray(params.attachments)
    ? params.attachments.slice(0, 100)
    : [];

  if (inputAttachments.length === 0) {
    return { content: nextContent, attachments: [] };
  }

  const bucket = storage.from(NOTE_MEDIA_BUCKET);
  const copiedPaths: string[] = [];
  const nextAttachments: AttachmentMeta[] = [];

  try {
    for (const raw of inputAttachments) {
      if (!raw || typeof raw !== 'object') continue;
      const oldPath = typeof raw.path === 'string' ? raw.path.trim().replace(/^\/+/, '') : '';
      if (!oldPath) {
        nextAttachments.push({ ...raw });
        continue;
      }

      if (!isValidNoteAttachmentPath(oldPath, sourceNoteId)) {
        throw new AppError(
          'permission-denied',
          'Attachment path does not belong to the source note.',
        );
      }

      const safeName =
        String(raw.name || oldPath.split('/').pop() || 'file')
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

      const oldCanonical = canonicalMediaUri(NOTE_MEDIA_BUCKET, oldPath);
      const newCanonical = canonicalMediaUri(NOTE_MEDIA_BUCKET, newPath);

      if (raw.url) {
        nextContent = replaceAllLiterals(nextContent, raw.url, newCanonical);
      }
      nextContent = replaceAllLiterals(nextContent, oldCanonical, newCanonical);

      nextAttachments.push({
        ...raw,
        path: newPath,
        url: newCanonical,
      });
    }

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
  const paths = [...pathSet];
  if (paths.length) {
    const { error } = await bucket.remove(paths);
    if (error) throw new AppError('internal', `Storage deletion failed: ${error.message}`);
    deleted += paths.length;
  }
  return deleted;
}
