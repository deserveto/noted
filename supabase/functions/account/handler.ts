import { fetchAllPages } from '../_shared/pagination.ts';
import { requireAuthenticatedUser, type VerifyBearerToken } from '../_shared/auth.ts';
import {
  AppError,
  errorResponse,
  handleCorsPreflight,
  jsonResponse,
} from '../_shared/cors.ts';
import {
  AVATARS_BUCKET,
  deleteNoteMediaObjects,
  deleteStoragePrefixRecursively,
  NOTE_MEDIA_BUCKET,
  type StorageAdmin,
} from '../_shared/media.ts';
import { exportNotes, isValidUuid, type ScopedNoteRecord } from '../_shared/policy.ts';

export interface AccountStore {
  ensureAccountInitialized(uid: string, email: string): Promise<void>;
  listExportableNotes(uid: string): Promise<ScopedNoteRecord[]>;
  beginAccountDeletion(uid: string): Promise<number>;
  listOwnedNotesForDeletion(
    uid: string,
  ): Promise<Array<{ note_id: string; attachments: unknown }>>;
  removeUserFromCollaborations(uid: string): Promise<void>;
  deleteAllUserData(uid: string): Promise<void>;
  deleteAuthUser(uid: string): Promise<void>;
}

export interface AccountDeps {
  verifyToken: VerifyBearerToken;
  verifyPassword: (email: string, password: string) => Promise<boolean>;
  store: AccountStore;
  storage: StorageAdmin;
}

export function createSupabaseAccountStore(admin: any): AccountStore {
  return {
    async ensureAccountInitialized(uid, email) {
      const normalized = email.trim().toLowerCase();
      await admin.from('profiles').upsert(
        {
          id: uid,
          email: normalized,
          name: normalized.split('@')[0] || 'Noted User',
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'id', ignoreDuplicates: true },
      );
      await admin.from('user_settings').upsert(
        {
          user_id: uid,
          notes_schema: 2,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id', ignoreDuplicates: true },
      );
    },
    async beginAccountDeletion(uid) {
      const { data, error } = await admin.rpc('audit_begin_account_deletion', { p_user_id: uid });
      if (error || !data || typeof data.pendingCopies !== 'number') throw new AppError('internal', error?.message ?? 'Invalid account deletion state.');
      return data.pendingCopies;
    },
    async listExportableNotes(uid) {
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
    async listOwnedNotesForDeletion(uid) {
      return await fetchAllPages(() => admin.from('notes').select('note_id, attachments').eq('user_id', uid), 'note_id');
    },
    async removeUserFromCollaborations(uid) {
      const { error } = await admin.rpc('audit_remove_user_memberships', { p_user_id: uid });
      if (error) throw new AppError('internal', error.message);
    },
    async deleteAllUserData(uid) {
      if (!isValidUuid(uid)) {
        throw new AppError('invalid-argument', 'Invalid user ID.');
      }
      const operations = [
        () => admin.from('note_presence').delete().eq('user_id', uid),
        () => admin.from('connection_requests').delete().or(`from_user_id.eq.${uid},to_user_id.eq.${uid}`),
        ...['user_invitations', 'notifications', 'ai_requests', 'ai_chats', 'user_favorites', 'notes', 'user_settings', 'rate_limits'].map(table => () => admin.from(table).delete().eq('user_id', uid)),
        () => admin.from('profiles').delete().eq('id', uid),
      ];
      for (const operation of operations) {
        const { error } = await operation();
        if (error) throw new AppError('internal', error.message);
      }
    },
    async deleteAuthUser(uid) {
      const { error } = await admin.auth.admin.deleteUser(uid);
      if (error && !/not\s*found/i.test(error.message ?? '')) {
        throw new AppError('internal', error.message);
      }
    },
  };
}

export async function handleAccountRequest(
  req: Request,
  deps: AccountDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    const caller = await requireAuthenticatedUser(req, deps.verifyToken);
    const payload = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const action = String(payload.action ?? '');

    if (action === 'prepareAccount') {
      await deps.store.ensureAccountInitialized(caller.uid, caller.email);
      return jsonResponse({ ok: true, updated: 0 });
    }

    if (action === 'exportData') {
      const notes = await deps.store.listExportableNotes(caller.uid);
      return jsonResponse(exportNotes(notes));
    }

    if (action === 'deleteAccount') {
      const currentPassword = String(payload.currentPassword ?? '');
      if (!currentPassword) {
        throw new AppError(
          'failed-precondition',
          'Reauthenticate with your current password before deleting your account.',
        );
      }

      const verified = await deps.verifyPassword(caller.email, currentPassword);
      if (!verified) {
        throw new AppError(
          'permission-denied',
          'Incorrect password. Account deletion was cancelled.',
        );
      }

      const pendingCopies = await deps.store.beginAccountDeletion(caller.uid);
      if (pendingCopies > 0) throw new AppError('unavailable', 'Account deletion is waiting for an in-progress copy cleanup. Please retry later.');
      const ownedNotes = await deps.store.listOwnedNotesForDeletion(caller.uid);
      for (const note of ownedNotes) {
        await deleteNoteMediaObjects({
          storage: deps.storage,
          noteId: note.note_id,
          ownerUserId: caller.uid,
          attachments: note.attachments,
        });
      }

      // Uploaders may have media on other users' notes or unreferenced drafts.
      // Sweep the full account prefix before removing database/auth references.
      await deleteStoragePrefixRecursively(
        deps.storage,
        NOTE_MEDIA_BUCKET,
        `users/${caller.uid}`,
      );

      await deleteStoragePrefixRecursively(
        deps.storage,
        AVATARS_BUCKET,
        `users/${caller.uid}`,
      );

      await deps.store.removeUserFromCollaborations(caller.uid);
      await deps.store.deleteAllUserData(caller.uid);
      await deps.store.deleteAuthUser(caller.uid);

      return jsonResponse({ ok: true });
    }

    throw new AppError('invalid-argument', `Unsupported account action: ${action}`);
  } catch (err) {
    return errorResponse(err);
  }
}
