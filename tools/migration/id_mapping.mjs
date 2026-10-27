import crypto from 'node:crypto';

/**
 * Fixed Noted UUIDv5 namespace for deterministic, repeatable Firebase UID -> Supabase UUID mapping.
 * Ensures re-running export/import produces identical UUIDs across Auth, Postgres FKs, RLS arrays,
 * JSONB role maps, and private Storage paths while preserving `note_id` deep links verbatim.
 */
export const NOTED_MIGRATION_NAMESPACE = '8c2d5c40-9b5a-4f1a-9d6e-2f08a11c9e77';

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function uuidToBytes(uuid) {
  const hex = uuid.replace(/-/g, '');
  return Buffer.from(hex, 'hex');
}

function bytesToUuid(buf) {
  const hex = buf.subarray(0, 16).toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

/**
 * Deterministically maps any Firebase UID (e.g., 28-char alphanumeric) to a valid RFC-4122 UUIDv5.
 * Already-valid UUIDs are normalized to lowercase verbatim.
 */
export function firebaseUidToSupabaseUuid(
  firebaseUid,
  namespace = NOTED_MIGRATION_NAMESPACE,
) {
  const raw = String(firebaseUid ?? '').trim();
  if (!raw) {
    throw new Error('Cannot map empty Firebase UID');
  }
  if (UUID_REGEX.test(raw)) {
    return raw.toLowerCase();
  }
  const nsBytes = uuidToBytes(namespace);
  const hash = crypto
    .createHash('sha1')
    .update(nsBytes)
    .update(Buffer.from(raw, 'utf8'))
    .digest();

  const bytes = Buffer.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // Version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
  return bytesToUuid(bytes);
}

export function canonicalPrivateMediaUri(bucket, objectPath) {
  const clean = String(objectPath ?? '').replace(/^\/+/, '');
  return `noted-media://${bucket}/${clean}`;
}

export function deterministicConnectionPairId(uidA, uidB) {
  return crypto
    .createHash('sha256')
    .update([String(uidA), String(uidB)].sort().join('_'))
    .digest('hex');
}

export function normalizeTimestamp(value, fallbackIso = new Date().toISOString()) {
  if (!value) return fallbackIso;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? fallbackIso : parsed.toISOString();
  }
  if (typeof value === 'number') {
    return new Date(value).toISOString();
  }
  if (typeof value === 'object') {
    const secs = value._seconds ?? value.seconds;
    const nanos = value._nanoseconds ?? value.nanoseconds ?? 0;
    if (typeof secs === 'number') {
      return new Date(secs * 1000 + Math.floor(nanos / 1e6)).toISOString();
    }
    if (typeof value.toDate === 'function') {
      return value.toDate().toISOString();
    }
  }
  return fallbackIso;
}

/**
 * Rewrites `users/<firebaseUid>/notes/<noteId>/<file>` or `users/<firebaseUid>/<avatar>`
 * to use the mapped Supabase UUID while keeping `<noteId>` and `<file>` intact.
 */
export function mapStorageObjectPath(firebasePath, resolveUid = firebaseUidToSupabaseUuid) {
  const clean = String(firebasePath ?? '').trim().replace(/^\/+/, '');
  if (!clean) return null;
  const parts = clean.split('/');
  if (parts[0] === 'users' && parts.length >= 3) {
    parts[1] = resolveUid(parts[1]);
    return parts.join('/');
  }
  return clean;
}

const EXTENSION_MIMES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.m4a': 'audio/m4a',
  '.mp4': 'audio/mp4',
  '.mp3': 'audio/mpeg',
  '.mpeg': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.aac': 'audio/aac',
};

const AVATAR_ALLOWED_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
]);

const NOTE_MEDIA_ALLOWED_MIMES = new Set([
  ...AVATAR_ALLOWED_MIMES,
  'audio/mp4',
  'audio/m4a',
  'audio/mpeg',
  'audio/wav',
  'audio/ogg',
  'audio/aac',
]);

/**
 * Resolves a bucket-compliant MIME type (`avatars` or `note-media`), never falling back
 * to `application/octet-stream` which private bucket policies reject.
 */
export function inferAllowedMimeType(
  filePath = '',
  explicitMime = '',
  bucket = 'note-media',
  attachmentType = 'image',
) {
  const allowed = bucket === 'avatars' ? AVATAR_ALLOWED_MIMES : NOTE_MEDIA_ALLOWED_MIMES;
  const normalizedMime = String(explicitMime || '').trim().toLowerCase();
  if (allowed.has(normalizedMime)) {
    return normalizedMime;
  }

  const cleanPath = String(filePath || '').split('?')[0].toLowerCase();
  const dotIdx = cleanPath.lastIndexOf('.');
  if (dotIdx >= 0) {
    const ext = cleanPath.slice(dotIdx);
    const byExt = EXTENSION_MIMES[ext];
    if (byExt && allowed.has(byExt)) {
      return byExt;
    }
  }

  if (bucket !== 'avatars' && String(attachmentType).toLowerCase() === 'audio') {
    return 'audio/m4a';
  }
  return 'image/png';
}

function escapeRegExp(str) {
  return String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Non-destructively replaces legacy Firebase Storage download URLs in `content`
 * (whether Quill Delta JSON `{"notedDocument":1,"ops":[...]}`, Markdown, or HTML)
 * ONLY for matched attachments, replacing them with `noted-media://note-media/<newPath>`.
 * Handles both exact URLs and token-rotated Firebase Storage URLs matching `oldPath`.
 * Never rewrites Quill ops structure, formatting, or `noted://app/notes/<id>` deep links.
 */
export function rewriteContentMediaUrls(content, rewrites) {
  let result = String(content ?? '');
  for (const { oldUrl, oldPath, newUri } of rewrites) {
    if (!newUri) continue;
    if (oldUrl && oldUrl !== newUri) {
      result = result.split(oldUrl).join(newUri);
      const jsonOld = JSON.stringify(oldUrl).slice(1, -1);
      const jsonNew = JSON.stringify(newUri).slice(1, -1);
      if (jsonOld !== oldUrl) {
        result = result.split(jsonOld).join(jsonNew);
      }
    }
    if (oldPath) {
      const cleanOldPath = String(oldPath).replace(/^\/+/, '');
      const encodedPath = encodeURIComponent(cleanOldPath);
      const pattern = new RegExp(
        `https://firebasestorage\\.googleapis\\.com/v0/b/[^/"'\\s\\\\]+/o/${escapeRegExp(encodedPath)}(?:\\?[^"'\\s\\\\)]*)?`,
        'g',
      );
      result = result.replace(pattern, newUri);
    }
  }
  return result;
}

const VALID_COLORS = new Set(['blue', 'pink', 'mint', 'yellow', 'peach', 'lav']);

/**
 * Maps a Firestore `notes/{noteId}` document into a `public.notes` row + media copy manifest.
 */
export function mapFirebaseNoteToPostgres(
  noteId,
  data,
  resolveUid = firebaseUidToSupabaseUuid,
) {
  const ownerId = resolveUid(data.userId);
  const liveMemberIds = Array.isArray(data.liveMemberIds)
    ? [...new Set(data.liveMemberIds.filter(Boolean).map((id) => resolveUid(id)))]
    : [];

  const liveRoles = {};
  if (data.liveRoles && typeof data.liveRoles === 'object') {
    for (const [fbUid, role] of Object.entries(data.liveRoles)) {
      if (role === 'edit' || role === 'view') {
        const mappedUid = resolveUid(fbUid);
        if (liveMemberIds.includes(mappedUid)) {
          liveRoles[mappedUid] = role;
        }
      }
    }
  }

  const sharedWithUserIds = Array.isArray(data.sharedWithUserIds)
    ? [...new Set(data.sharedWithUserIds.filter(Boolean).map((id) => resolveUid(id)))]
    : [];

  const pendingSharedWithUserIds = Array.isArray(data.pendingSharedWithUserIds)
    ? [...new Set(data.pendingSharedWithUserIds.filter(Boolean).map((id) => resolveUid(id)))]
    : [];

  const rawAttachments = Array.isArray(data.attachments) ? data.attachments.slice(0, 100) : [];
  const mediaObjects = [];
  const urlRewrites = [];
  const attachments = rawAttachments
    .filter((a) => a && typeof a === 'object')
    .map((a) => {
      const oldPath = typeof a.path === 'string' && a.path.trim() ? a.path.trim() : null;
      const oldUrl = typeof a.url === 'string' && a.url.trim() ? a.url.trim() : '';
      const mappedPath = oldPath ? mapStorageObjectPath(oldPath, resolveUid) : null;
      const newUri = mappedPath ? canonicalPrivateMediaUri('note-media', mappedPath) : oldUrl;
      const attType = String(a.type ?? 'image');
      if (oldPath && mappedPath) {
        mediaObjects.push({
          bucket: 'note-media',
          sourcePath: oldPath,
          targetPath: mappedPath,
          sourceUrl: oldUrl || null,
          attachmentType: attType,
        });
      }
      if ((oldUrl || oldPath) && mappedPath) {
        urlRewrites.push({ oldUrl, oldPath, newUri });
      }
      return {
        type: attType,
        name: String(a.name ?? 'file').slice(0, 160),
        path: mappedPath ?? '',
        url: newUri,
        ...(typeof a.duration === 'number' ? { duration: a.duration } : {}),
      };
    });

  const rewrittenContent = rewriteContentMediaUrls(data.content ?? '', urlRewrites);
  const createdAt = normalizeTimestamp(data.createdAt);
  const updatedAt = normalizeTimestamp(data.updatedAt, createdAt);
  const deletedAt = data.deletedAt ? normalizeTimestamp(data.deletedAt) : null;

  const row = {
    note_id: String(noteId),
    user_id: ownerId,
    owner_name: String(data.ownerName ?? '').slice(0, 200),
    owner_email: String(data.ownerEmail ?? '').trim().toLowerCase().slice(0, 320),
    title: String(data.title ?? '').slice(0, 1000),
    content: rewrittenContent,
    category: String(data.category ?? 'Personal').slice(0, 200),
    color: VALID_COLORS.has(data.color) ? data.color : 'blue',
    is_favorite: Boolean(data.isFavorite),
    live_member_ids: liveMemberIds,
    live_roles: liveRoles,
    shared_with_user_ids: sharedWithUserIds,
    pending_shared_with_user_ids: pendingSharedWithUserIds,
    source_owner_id: data.sourceOwnerId ? resolveUid(data.sourceOwnerId) : null,
    source_note_id: data.sourceNoteId ? String(data.sourceNoteId) : null,
    attachments,
    revision: Number.isInteger(data.revision) && data.revision >= 0 ? data.revision : 0,
    last_edited_by: data.lastEditedBy ? resolveUid(data.lastEditedBy) : null,
    deleted_at: deletedAt,
    created_at: createdAt,
    updated_at: updatedAt,
  };

  return { row, mediaObjects };
}

export function computeEntityChecksum(payload) {
  return crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}
