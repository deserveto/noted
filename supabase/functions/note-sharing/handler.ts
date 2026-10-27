import { claimNoteDeletion, finalizeNoteDeletion } from '../_shared/note_deletion.ts';
import { requireAuthenticatedUser, type VerifyBearerToken } from '../_shared/auth.ts';
import {
  AppError,
  errorResponse,
  handleCorsPreflight,
  jsonResponse,
} from '../_shared/cors.ts';
import type { EmailEnv } from '../_shared/email.ts';
import {
  copyAttachmentsForNote,
  deleteNoteMediaObjects,
  type StorageAdmin,
} from '../_shared/media.ts';
import {
  draftForCopy,
  isValidUuid,
  VALID_COLORS,
  type AttachmentMeta,
} from '../_shared/policy.ts';

export interface NoteRow {
  note_id: string;
  user_id: string;
  owner_name: string;
  owner_email: string;
  title: string;
  content: string;
  category: string;
  color: string;
  is_favorite: boolean;
  live_member_ids: string[];
  live_roles: Record<string, string>;
  shared_with_user_ids: string[];
  pending_shared_with_user_ids: string[];
  source_owner_id: string | null;
  source_note_id: string | null;
  attachments: AttachmentMeta[];
  revision: number;
  last_edited_by: string | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface NoteSharingStore {
  checkRateLimit(uid: string, op: string, limit: number): Promise<boolean>;
  getNote(noteId: string): Promise<NoteRow | null>;
  setLiveRole(noteId: string, actorId: string, targetId: string, role: string): Promise<{changed: boolean; note: NoteRow}>;
  queueNoteCopy(noteId: string, actorId: string, targetId: string): Promise<{changed: boolean; note: NoteRow}>;
  acceptNoteCopy(noteId: string, actorId: string, revision: number, copy: Record<string, unknown>): Promise<void>;
  duplicateNote(noteId: string, actorId: string, revision: number, copy: Record<string, unknown>): Promise<void>;
  reserveCopyCleanup(noteId: string, userId: string): Promise<void>;
  completeCopyCleanup(noteId: string): Promise<void>;
  claimNoteDeletion(noteId: string, ownerId: string): Promise<{ claimed: boolean; note: NoteRow | null }>;
  finalizeNoteDeletion(noteId: string, ownerId: string): Promise<boolean>;
  deletePresence(noteId: string, userId: string): Promise<void>;
  hasAcceptedConnection(uidA: string, uidB: string): Promise<boolean>;
  getUserSettings(
    uid: string,
  ): Promise<{ preferences: Record<string, unknown>; timezoneOffsetMinutes: number }>;
  getProfile(
    uid: string,
  ): Promise<{ id: string; email: string; name: string } | null>;
  insertNotification(params: {
    userId: string;
    type: 'request' | 'copy' | 'live' | 'system';
    title: string;
    body: string;
    noteId?: string | null;
    actorId?: string | null;
    actorName?: string | null;
    emailDispatched?: boolean;
  }): Promise<string>;
}

export interface NoteSharingDeps {
  verifyToken: VerifyBearerToken;
  store: NoteSharingStore;
  storage: StorageAdmin;
  env: EmailEnv;
  fetchImpl?: typeof fetch;
}

export function createSupabaseNoteSharingStore(admin: any): NoteSharingStore {
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
    async getNote(noteId) {
      const { data } = await admin
        .from('notes')
        .select('*')
        .eq('note_id', noteId)
        .maybeSingle();
      return (data as NoteRow | null) ?? null;
    },
    async setLiveRole(noteId, actorId, targetId, role) {
      const { data, error } = await admin.rpc('audit_set_live_role', { p_note_id: noteId, p_actor_id: actorId, p_target_id: targetId, p_role: role });
      if (error) throw new AppError('permission-denied', error.message);
      return data;
    },
    async queueNoteCopy(noteId, actorId, targetId) {
      const { data, error } = await admin.rpc('audit_queue_note_copy', { p_note_id: noteId, p_actor_id: actorId, p_target_id: targetId });
      if (error) throw new AppError('permission-denied', error.message);
      return data;
    },
    async acceptNoteCopy(noteId, actorId, revision, copy) {
      const { error } = await admin.rpc('audit_accept_note_copy', { p_note_id: noteId, p_actor_id: actorId, p_expected_revision: revision, p_copy: copy });
      if (error) throw new AppError('failed-precondition', error.message);
    },
    async reserveCopyCleanup(noteId, userId) {
      const { error } = await admin.rpc('audit_reserve_copy_cleanup', { p_note_id: noteId, p_user_id: userId });
      if (error) throw new AppError('internal', error.message);
    },
    async completeCopyCleanup(noteId) {
      const { error } = await admin.rpc('audit_complete_copy_cleanup', { p_note_id: noteId });
      if (error) throw new AppError('internal', error.message);
    },
    async duplicateNote(noteId, actorId, revision, copy) {
      const { error } = await admin.rpc('audit_duplicate_note', { p_note_id: noteId, p_actor_id: actorId, p_expected_revision: revision, p_copy: copy });
      if (error) throw new AppError('failed-precondition', error.message);
    },
    async claimNoteDeletion(noteId, ownerId) { return await claimNoteDeletion(admin, noteId, ownerId); },
    async finalizeNoteDeletion(noteId, ownerId) { return await finalizeNoteDeletion(admin, noteId, ownerId); },
    async deletePresence(noteId, userId) {
      await admin
        .from('note_presence')
        .delete()
        .eq('note_id', noteId)
        .eq('user_id', userId);
    },
    async hasAcceptedConnection(uidA, uidB) {
      if (!isValidUuid(uidA) || !isValidUuid(uidB)) {
        return false;
      }
      const { data } = await admin
        .from('connection_requests')
        .select('connection_id')
        .eq('status', 'accepted')
        .or(
          `and(from_user_id.eq.${uidA},to_user_id.eq.${uidB}),and(from_user_id.eq.${uidB},to_user_id.eq.${uidA})`,
        )
        .limit(1);
      return Array.isArray(data) && data.length > 0;
    },
    async getUserSettings(uid) {
      const { data } = await admin
        .from('user_settings')
        .select('preferences, timezone_offset_minutes')
        .eq('user_id', uid)
        .maybeSingle();
      return {
        preferences: (data?.preferences ?? {}) as Record<string, unknown>,
        timezoneOffsetMinutes: Number(data?.timezone_offset_minutes ?? 0),
      };
    },
    async getProfile(uid) {
      const { data } = await admin
        .from('profiles')
        .select('id, email, name')
        .eq('id', uid)
        .maybeSingle();
      return data ?? null;
    },
    async insertNotification(params) {
      const id = crypto.randomUUID().replace(/-/g, '');
      const { error } = await admin.from('notifications').insert({
        id,
        user_id: params.userId,
        type: params.type,
        title: params.title,
        body: params.body,
        note_id: params.noteId ?? null,
        actor_id: params.actorId ?? null,
        actor_name: params.actorName ?? null,
        read: false,
        email_dispatched: Boolean(params.emailDispatched),
        created_at: new Date().toISOString(),
      });
      if (error) throw new AppError('internal', error.message);
      return id;
    },
  };
}

async function notifyAndMaybeEmail(
  deps: NoteSharingDeps,
  params: {
    userId: string;
    type: 'request' | 'copy' | 'live';
    title: string;
    body: string;
    noteId?: string | null;
    actorId?: string | null;
    actorName?: string | null;
  },
) {
  const { preferences } = await deps.store.getUserSettings(params.userId);
  const prefKey = params.type === 'request' ? 'nRequests' : params.type === 'copy' ? 'nCopies' : 'nLive';
  if (preferences[prefKey] === false) return;
  await deps.store.insertNotification({ ...params,
    title: params.title.slice(0, 300), body: params.body.slice(0, 1000),
    actorName: params.actorName?.slice(0, 200), emailDispatched: false });
}

export async function handleNoteSharingRequest(
  req: Request,
  deps: NoteSharingDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    const caller = await requireAuthenticatedUser(req, deps.verifyToken);
    const payload = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const action = String(payload.action ?? '');

    if (action === 'setLiveRole') {
      if (!(await deps.store.checkRateLimit(caller.uid, 'setLiveRole', 60))) throw new AppError('resource-exhausted', 'Too many sharing requests. Try again shortly.');
      const noteId = String(payload.noteId ?? '').trim();
      const targetUserId = String(payload.targetUserId ?? '').trim();
      const role = String(payload.role ?? '').trim();
      if (
        !noteId ||
        !isValidUuid(targetUserId) ||
        targetUserId === caller.uid ||
        !['edit', 'view', 'none'].includes(role)
      ) {
        throw new AppError('invalid-argument', 'Invalid sharing request.');
      }

      const note = await deps.store.getNote(noteId);
      if (!note || note.user_id !== caller.uid || note.deleted_at) {
        throw new AppError('permission-denied', 'Only the owner can share this note.');
      }

      if (role !== 'none') {
        if (note.source_owner_id && note.source_owner_id !== caller.uid) {
          const sourceSettings = await deps.store.getUserSettings(note.source_owner_id);
          if (sourceSettings.preferences.reshare === false) {
            throw new AppError(
              'permission-denied',
              'The original author disabled resharing.',
            );
          }
        }
        if (!(await deps.store.hasAcceptedConnection(caller.uid, targetUserId))) {
          throw new AppError('permission-denied', 'Connect first before sharing.');
        }
      }

      const result = await deps.store.setLiveRole(noteId, caller.uid, targetUserId, role);

      if (role !== 'none' && result.changed) {
        const ownerProfile = await deps.store.getProfile(caller.uid).catch(() => null);
        const actorName = ownerProfile?.name || caller.email || 'Someone';
        await notifyAndMaybeEmail(deps, {
          userId: targetUserId,
          type: 'live',
          title: `${actorName} shared a live note`,
          body: note.title || 'Untitled',
          noteId,
          actorId: caller.uid,
          actorName,
        }).catch(() => undefined);
      }

      return jsonResponse({ ok: true });
    }

    if (action === 'queueNoteCopy') {
      if (!(await deps.store.checkRateLimit(caller.uid, 'queueNoteCopy', 60))) throw new AppError('resource-exhausted', 'Too many sharing requests. Try again shortly.');
      const noteId = String(payload.noteId ?? '').trim();
      const targetUserId = String(payload.targetUserId ?? '').trim();
      if (!noteId || !isValidUuid(targetUserId) || targetUserId === caller.uid) {
        throw new AppError('invalid-argument', 'Invalid copy request.');
      }

      const note = await deps.store.getNote(noteId);
      if (!note || note.user_id !== caller.uid || note.deleted_at) {
        throw new AppError('permission-denied', 'Only the owner can send a copy.');
      }

      if (note.source_owner_id && note.source_owner_id !== caller.uid) {
        const sourceSettings = await deps.store.getUserSettings(note.source_owner_id);
        if (sourceSettings.preferences.reshare === false) {
          throw new AppError(
            'permission-denied',
            'The original author disabled resharing.',
          );
        }
      }

      if (!(await deps.store.hasAcceptedConnection(caller.uid, targetUserId))) {
        throw new AppError('permission-denied', 'Connect first before sharing.');
      }

      const recipientSettings = await deps.store.getUserSettings(targetUserId);
      if (recipientSettings.preferences.copies === false) {
        throw new AppError(
          'permission-denied',
          'This person is not accepting note copies.',
        );
      }

      const result = await deps.store.queueNoteCopy(noteId, caller.uid, targetUserId);
      if (!result.changed) return jsonResponse({ ok: true });

      const ownerProfile = await deps.store.getProfile(caller.uid).catch(() => null);
      const actorName = ownerProfile?.name || caller.email || 'Someone';
      await notifyAndMaybeEmail(deps, {
        userId: targetUserId,
        type: 'copy',
        title: `${actorName} sent a note copy`,
        body: note.title || 'Untitled',
        noteId,
        actorId: caller.uid,
        actorName,
      }).catch(() => undefined);

      return jsonResponse({ ok: true });
    }

    if (action === 'acceptNoteCopy') {
      if (!(await deps.store.checkRateLimit(caller.uid, 'acceptNoteCopy', 60))) throw new AppError('resource-exhausted', 'Too many sharing requests. Try again shortly.');
      const noteId = String(payload.noteId ?? '').trim();
      if (!noteId) {
        throw new AppError('invalid-argument', 'Note ID is required.');
      }

      const note = await deps.store.getNote(noteId);
      if (!note || note.deleted_at) {
        throw new AppError('not-found', 'Note not found.');
      }

      const pending = Array.isArray(note.pending_shared_with_user_ids)
        ? note.pending_shared_with_user_ids
        : [];
      if (!pending.includes(caller.uid)) {
        throw new AppError('permission-denied', 'No pending copy for this account.');
      }

      const newNoteId = crypto.randomUUID().replace(/-/g, '');
      await deps.store.reserveCopyCleanup(newNoteId, caller.uid);
      const copied = await copyAttachmentsForNote({
        storage: deps.storage,
        sourceNoteId: noteId,
        targetUserId: caller.uid,
        targetNoteId: newNoteId,
        content: note.content ?? '',
        attachments: note.attachments ?? [],
      });

      const me = await deps.store.getProfile(caller.uid);
      const now = new Date().toISOString();
      try {
        await deps.store.acceptNoteCopy(noteId, caller.uid, note.revision, {
          note_id: newNoteId,
          user_id: caller.uid,
          owner_name: me?.name ?? '',
          owner_email: me?.email ?? caller.email ?? '',
          title: note.title ?? '',
          content: copied.content,
          category: note.category ?? 'Personal',
          color: VALID_COLORS.has(note.color) ? note.color : 'blue',
          is_favorite: false,
          live_member_ids: [],
          live_roles: {},
          shared_with_user_ids: [],
          pending_shared_with_user_ids: [],
          source_owner_id: note.source_owner_id || note.user_id,
          source_note_id: note.source_note_id || noteId,
          attachments: copied.attachments,
          revision: 0,
          last_edited_by: caller.uid,
          deleted_at: null,
          created_at: now,
          updated_at: now,
        });
      } catch (err) {
        await deleteNoteMediaObjects({
          storage: deps.storage,
          noteId: newNoteId,
          attachments: copied.attachments,
        }).catch(() => undefined);
        throw err;
      }

      await deps.store.completeCopyCleanup(newNoteId).catch(() => undefined);
      const actorName = me?.name || caller.email || 'A collaborator';
      await notifyAndMaybeEmail(deps, {
        userId: note.user_id,
        type: 'copy',
        title: 'Copy accepted',
        body: `${actorName} added ${note.title || 'your note'}.`,
        noteId: newNoteId,
        actorId: caller.uid,
        actorName,
      }).catch(() => undefined);

      return jsonResponse({ ok: true, noteId: newNoteId });
    }

    if (action === 'duplicateNote') {
      const allowed = await deps.store.checkRateLimit(caller.uid, 'duplicateNote', 60);
      if (!allowed) {
        throw new AppError(
          'resource-exhausted',
          'Too many note copies. Try again shortly.',
        );
      }

      const noteId = String(payload.noteId ?? '').trim();
      if (!noteId) {
        throw new AppError('invalid-argument', 'Note ID is required.');
      }

      const note = await deps.store.getNote(noteId);
      if (!note || note.deleted_at) {
        throw new AppError('not-found', 'Note not found.');
      }

      const isMember =
        note.user_id === caller.uid ||
        (Array.isArray(note.live_member_ids) && note.live_member_ids.includes(caller.uid));
      if (!isMember) {
        throw new AppError('permission-denied', 'You cannot duplicate this note.');
      }

      const draft =
        payload.draft && typeof payload.draft === 'object'
          ? draftForCopy(payload.draft as Record<string, unknown>)
          : {
              title: note.title ?? '',
              content: note.content ?? '',
              category: note.category ?? 'Personal',
              color: VALID_COLORS.has(note.color) ? note.color : 'blue',
              attachments: Array.isArray(note.attachments) ? note.attachments : [],
            };

      const newNoteId = crypto.randomUUID().replace(/-/g, '');
      await deps.store.reserveCopyCleanup(newNoteId, caller.uid);
      const copied = await copyAttachmentsForNote({
        storage: deps.storage,
        sourceNoteId: noteId,
        targetUserId: caller.uid,
        targetNoteId: newNoteId,
        content: draft.content,
        attachments: draft.attachments,
      });

      const hasExplicitDraftTitle =
        Boolean(payload.draft) &&
        typeof payload.draft === 'object' &&
        typeof (payload.draft as Record<string, unknown>).title === 'string' &&
        String((payload.draft as Record<string, unknown>).title).trim().length > 0;

      const me = await deps.store.getProfile(caller.uid);
      const now = new Date().toISOString();
      const baseTitle = draft.title || 'Untitled';
      const finalTitle =
        payload.preserveExactTitle || hasExplicitDraftTitle
          ? baseTitle.slice(0, 1000)
          : `${baseTitle} (Copy)`.slice(0, 1000);

      try {
        await deps.store.duplicateNote(noteId, caller.uid, note.revision, {
          note_id: newNoteId,
          user_id: caller.uid,
          owner_name: me?.name ?? '',
          owner_email: me?.email ?? caller.email ?? '',
          title: finalTitle,
          content: copied.content,
          category: draft.category,
          color: draft.color,
          is_favorite: false,
          live_member_ids: [],
          live_roles: {},
          shared_with_user_ids: [],
          pending_shared_with_user_ids: [],
          source_owner_id:
            note.user_id !== caller.uid
              ? note.source_owner_id || note.user_id
              : note.source_owner_id || null,
          source_note_id:
            note.user_id !== caller.uid
              ? note.source_note_id || noteId
              : note.source_note_id || null,
          attachments: copied.attachments,
          revision: 0,
          last_edited_by: caller.uid,
          deleted_at: null,
          created_at: now,
          updated_at: now,
        });
      } catch (err) {
        await deleteNoteMediaObjects({
          storage: deps.storage,
          noteId: newNoteId,
          attachments: copied.attachments,
        }).catch(() => undefined);
        throw err;
      }

      await deps.store.completeCopyCleanup(newNoteId).catch(() => undefined);
      return jsonResponse({ ok: true, noteId: newNoteId });
    }

    if (action === 'deleteNote') {
      const noteId = String(payload.noteId ?? '').trim();
      if (!noteId) {
        throw new AppError('invalid-argument', 'Note ID is required.');
      }

      const note = await deps.store.getNote(noteId);
      if (!note) return jsonResponse({ ok: true });

      if (note.user_id !== caller.uid || !note.deleted_at) {
        throw new AppError(
          'permission-denied',
          'Move the note to Recently Deleted first.',
        );
      }

      const claim = await deps.store.claimNoteDeletion(noteId, caller.uid);
      if (!claim.claimed || !claim.note) throw new AppError('already-exists', 'The note changed before deletion.');
      await deleteNoteMediaObjects({
        storage: deps.storage,
        noteId,
        ownerUserId: caller.uid,
        attachments: claim.note.attachments,
      });
      await deps.store.finalizeNoteDeletion(noteId, caller.uid);

      return jsonResponse({ ok: true });
    }

    throw new AppError('invalid-argument', `Unsupported sharing action: ${action}`);
  } catch (err) {
    return errorResponse(err);
  }
}
