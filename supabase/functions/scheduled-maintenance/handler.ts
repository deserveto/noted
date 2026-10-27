import { claimNoteDeletion, finalizeNoteDeletion } from '../_shared/note_deletion.ts';
import { fetchAllPages } from '../_shared/pagination.ts';
import { requireCronSecret } from '../_shared/auth.ts';
import {
  AppError,
  errorResponse,
  handleCorsPreflight,
  jsonResponse,
} from '../_shared/cors.ts';
import {
  buildNotificationEmailHtml,
  isNotificationEmailEnabled,
  sendResendEmail,
  type EmailEnv,
} from '../_shared/email.ts';
import { deleteNoteMediaObjects, deleteStoragePrefixRecursively, NOTE_MEDIA_BUCKET, type StorageAdmin } from '../_shared/media.ts';
import { emailAllowed, escapeHtml } from '../_shared/policy.ts';

export interface QueuedNotificationRow {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string;
  note_id: string | null;
}

export interface RecapCandidateUser {
  userId: string;
  email: string;
  preferences: Record<string, unknown>;
  timezoneOffsetMinutes: number;
}

export interface ScheduledMaintenanceStore {
  listPendingEmailNotifications(limit: number, offset: number): Promise<QueuedNotificationRow[]>;
  markNotificationEmailDispatched(id: string): Promise<void>;
  getRecipientContext(uid: string): Promise<{
    email: string;
    preferences: Record<string, unknown>;
    timezoneOffsetMinutes: number;
  } | null>;
  listRecapCandidates(): Promise<RecapCandidateUser[]>;
  listOwnedNotesUpdatedSince(
    uid: string,
    sinceIso: string,
    limit: number,
  ): Promise<Array<{ title: string }>>;
  listExpiredDeletedNotes(
    cutoffIso: string,
    limit: number,
  ): Promise<Array<{ note_id: string; user_id?: string; attachments: unknown }>>;
  claimNoteDeletion(noteId: string, ownerId: string, before: string): Promise<{ claimed: boolean; note: { attachments: unknown } | null }>;
  finalizeNoteDeletion(noteId: string, ownerId: string): Promise<boolean>;
  listCopyCleanup(before: string, limit: number): Promise<Array<{ note_id: string; user_id: string }>>;
  claimCopyCleanup(noteId: string, before: string): Promise<{ claimed: boolean; userId: string | null }>;
  finishCopyCleanup(noteId: string): Promise<void>;
  listCopySweeps(limit: number): Promise<Array<{ note_id: string; user_id: string }>>;
  recordCopySweep(noteId: string): Promise<void>;
  cleanupEphemeralRows(): Promise<void>;
}

export interface ScheduledMaintenanceDeps {
  cronSecret?: string;
  store: ScheduledMaintenanceStore;
  storage: StorageAdmin;
  env: EmailEnv;
  fetchImpl?: typeof fetch;
  now?: () => Date;
}

export function createSupabaseScheduledMaintenanceStore(
  admin: any,
): ScheduledMaintenanceStore {
  return {
    async listPendingEmailNotifications(limit, _offset) {
      const { data, error } = await admin.rpc('audit_take_email_batch', { p_limit: limit });
      if (error || !data) throw new AppError('internal', error?.message ?? 'Notification query failed.');
      return data as QueuedNotificationRow[];
    },
    async markNotificationEmailDispatched(id) {
      const { error } = await admin.from('notifications')
        .update({ email_dispatched: true }).eq('id', id);
      if (error) throw new AppError('internal', error.message);
    },
    async getRecipientContext(uid) {
      const [{ data: profile }, { data: settings }] = await Promise.all([
        admin.from('profiles').select('email').eq('id', uid).maybeSingle(),
        admin
          .from('user_settings')
          .select('preferences, timezone_offset_minutes')
          .eq('user_id', uid)
          .maybeSingle(),
      ]);
      if (!profile?.email) return null;
      return {
        email: String(profile.email),
        preferences: (settings?.preferences ?? {}) as Record<string, unknown>,
        timezoneOffsetMinutes: Number(settings?.timezone_offset_minutes ?? 0),
      };
    },
    async listRecapCandidates() {
      const settingsRows = await fetchAllPages(
        () => admin.from('user_settings').select('user_id, preferences, timezone_offset_minutes').contains('preferences', { nRecap: true }), 'user_id');
      const activeRows = settingsRows.filter((row: any) => row?.preferences?.nRecap === true);
      const profiles = await fetchAllPages(() => admin.from('profiles').select('id, email'), 'id');

      const emailById = new Map<string, string>();
      for (const p of profiles ?? []) {
        if (p?.id && p?.email) {
          emailById.set(String(p.id), String(p.email));
        }
      }

      const candidates: RecapCandidateUser[] = [];
      for (const row of activeRows) {
        const uid = String(row.user_id);
        const email = emailById.get(uid);
        if (!email) continue;
        candidates.push({
          userId: uid,
          email,
          preferences: (row.preferences ?? {}) as Record<string, unknown>,
          timezoneOffsetMinutes: Number(row.timezone_offset_minutes ?? 0),
        });
      }
      return candidates;
    },
    async listOwnedNotesUpdatedSince(uid, sinceIso, limit) {
      return await fetchAllPages(() => admin.from('notes').select('note_id, title')
        .eq('user_id', uid).is('deleted_at', null).gte('updated_at', sinceIso), 'note_id');
    },
    async listExpiredDeletedNotes(cutoffIso, limit) {
      const { data } = await admin
        .from('notes')
        .select('note_id, user_id, attachments')
        .lte('deleted_at', cutoffIso)
        .limit(limit);
      return (data ?? []) as Array<{
        note_id: string;
        user_id?: string;
        attachments: unknown;
      }>;
    },
    async claimNoteDeletion(noteId, ownerId, before) { return await claimNoteDeletion(admin, noteId, ownerId, before); },
    async finalizeNoteDeletion(noteId, ownerId) { return await finalizeNoteDeletion(admin, noteId, ownerId); },
    async listCopyCleanup(before, limit) {
      const { data, error } = await admin.rpc('audit_list_copy_cleanup', { p_older_than: before, p_limit: limit });
      if (error || !data) throw new AppError('internal', error?.message ?? 'Cleanup query failed.');
      return data;
    },
    async claimCopyCleanup(noteId, before) {
      const { data, error } = await admin.rpc('audit_claim_copy_cleanup', { p_note_id: noteId, p_older_than: before });
      if (error || !data) throw new AppError('internal', error?.message ?? 'Cleanup claim failed.');
      return data;
    },
    async finishCopyCleanup(noteId) {
      const { error } = await admin.rpc('audit_finish_copy_cleanup', { p_note_id: noteId });
      if (error) throw new AppError('internal', error.message);
    },
    async listCopySweeps(limit) {
      const { data, error } = await admin.rpc('audit_list_copy_sweeps', { p_limit: limit });
      if (error || !data) throw new AppError('internal', error?.message ?? 'Copy sweep query failed.');
      return data;
    },
    async recordCopySweep(noteId) {
      const { error } = await admin.rpc('audit_record_copy_sweep', { p_note_id: noteId });
      if (error) throw new AppError('internal', error.message);
    },
    async cleanupEphemeralRows() {
      try {
        await admin.rpc('cleanup_ephemeral_rows');
      } catch {
        // Ignore if cleanup RPC is unavailable in test mocks
      }
    },
  };
}

export async function handleScheduledMaintenanceRequest(
  req: Request,
  deps: ScheduledMaintenanceDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    requireCronSecret(req, deps.cronSecret);
    const payload = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const job = String(payload.job ?? 'hourly');
    const now = deps.now ? deps.now() : new Date();

    if (job === 'hourly') {
      // 1. Dispatch queued activity emails from SQL triggers (`connectionAccepted`, `liveNoteEdited`)
      let emailsSent = 0;
      let offset = 0;
      let attempts = 0;
      let examined = 0;
      const visited = new Set<string>();
      let wrapped = false;
      while (attempts < 200 && examined < 1000) {
        const queued = await deps.store.listPendingEmailNotifications(200, offset);
        if (queued.length === 0) break;
        let removed = 0;
        for (const notif of queued) {
          if (examined >= 1000) break;
          if (visited.has(notif.id)) { wrapped = true; break; }
          visited.add(notif.id);
          examined++;
          const ctx = await deps.store.getRecipientContext(notif.user_id);
          if (
            ctx?.email &&
            isNotificationEmailEnabled(
              notif.type,
              ctx.preferences,
              ctx.timezoneOffsetMinutes,
              now,
            )
          ) {
            if (attempts >= 200) break;
            attempts++;
            const result = await sendResendEmail({
              fetchImpl: deps.fetchImpl,
              env: deps.env,
              to: ctx.email,
              subject: notif.title,
              html: buildNotificationEmailHtml({
                title: notif.title,
                body: notif.body,
                appUrl: deps.env.appUrl,
                noteId: notif.note_id,
              }),
              idempotencyKey: `activity-${notif.id}`,
            }).catch(() => ({ sent: false, reason: 'error' }));
            if (result.sent) {
              emailsSent++;
              await deps.store.markNotificationEmailDispatched(notif.id);
              removed++;
            }
          } else if (ctx && ((notif.type === 'request' && ctx.preferences.nRequests === false) ||
            (notif.type === 'copy' && ctx.preferences.nCopies === false) ||
            (notif.type === 'live' && ctx.preferences.nLive === false))) {
            await deps.store.markNotificationEmailDispatched(notif.id);
            removed++;
          }
        }
        if (wrapped || attempts >= 200 || examined >= 1000 || queued.length < 200) break;
        offset += queued.length - removed;
      }

      // 2. Weekly recap (Sunday 09:00 in user's local timezone)
      let recapsSent = 0;
      const sinceIso = new Date(now.getTime() - 7 * 86400000).toISOString();
      const candidates = await deps.store.listRecapCandidates();
      for (const user of candidates) {
        const local = new Date(
          now.getTime() + user.timezoneOffsetMinutes * 60000,
        );
        if (local.getUTCDay() !== 0 || local.getUTCHours() !== 9) continue;
        if (!emailAllowed(user.preferences, user.timezoneOffsetMinutes, now)) {
          continue;
        }

        const recentNotes = await deps.store.listOwnedNotesUpdatedSince(
          user.userId,
          sinceIso,
          25,
        );
        if (recentNotes.length === 0) continue;

        const weekKey = local.toISOString().slice(0, 10);
        const titles = recentNotes
          .slice(0, 6)
          .map((n) => `<li>${escapeHtml(n.title || 'Untitled')}</li>`)
          .join('');
        const appUrl = deps.env.appUrl?.trim().replace(/\/+$/, '') ?? '';

        const result = await sendResendEmail({
          fetchImpl: deps.fetchImpl,
          env: deps.env,
          to: user.email,
          subject: 'Your Noted weekly recap',
          html:
            `<div style="font-family:Georgia,serif;color:#1C1917;line-height:1.6;max-width:480px">` +
            `<p style="font-size:18px;margin:0 0 8px"><strong>Your week in Noted</strong></p>` +
            `<p style="color:#57534E;margin:0 0 12px">${recentNotes.length} note${recentNotes.length === 1 ? '' : 's'} updated in the last week.</p>` +
            `<ul style="color:#1C1917;padding-left:18px">${titles}</ul>` +
            (appUrl.startsWith('https://')
              ? `<p><a href="${escapeHtml(appUrl)}" style="color:#2D6A4F;font-weight:600">Open Noted</a></p>`
              : '') +
            `</div>`,
          idempotencyKey: `recap-${user.userId}-${weekKey}`,
        }).catch(() => ({ sent: false }));
        if (result.sent) recapsSent++;
      }

      // Allow a conservative grace period before claiming abandoned copies.
      const staleBefore = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
      for (const reservation of await deps.store.listCopyCleanup(staleBefore, 200)) {
        const claim = await deps.store.claimCopyCleanup(reservation.note_id, staleBefore);
        if (!claim.claimed || !claim.userId) continue;
        try {
          await deleteStoragePrefixRecursively(deps.storage, NOTE_MEDIA_BUCKET,
            `users/${claim.userId}/notes/${reservation.note_id}`);
          await deps.store.finishCopyCleanup(reservation.note_id);
        } catch {
          // Keep the claimed reservation for the next scheduled retry.
        }
      }

      // Retain abandoned destinations permanently: a Storage operation accepted
      // before cleanup may complete late. Revisit each prefix in fair batches.
      for (const tombstone of await deps.store.listCopySweeps(200)) {
        try {
          await deleteStoragePrefixRecursively(deps.storage, NOTE_MEDIA_BUCKET,
            `users/${tombstone.user_id}/notes/${tombstone.note_id}`);
        } catch {
          // Leave the tombstone in place for a later pass.
        } finally {
          await deps.store.recordCopySweep(tombstone.note_id);
        }
      }

      // 3. Cleanup expired presence & deduplication windows
      await deps.store.cleanupEphemeralRows();

      return jsonResponse({ ok: true, emailsSent, recapsSent });
    }

    if (job === 'purge') {
      const cutoffIso = new Date(now.getTime() - 30 * 86400000).toISOString();
      const expired = await deps.store.listExpiredDeletedNotes(cutoffIso, 400);
      let mediaDeleted = 0;
      let purgedNotes = 0;
      for (const note of expired) {
        if (!note.user_id) throw new AppError('internal', 'Expired note has no owner.');
        const claim = await deps.store.claimNoteDeletion(note.note_id, note.user_id, cutoffIso);
        if (!claim.claimed || !claim.note) continue;
        mediaDeleted += await deleteNoteMediaObjects({
          storage: deps.storage, noteId: note.note_id,
          ownerUserId: note.user_id, attachments: claim.note.attachments,
        });
        if (await deps.store.finalizeNoteDeletion(note.note_id, note.user_id)) purgedNotes++;
      }

      return jsonResponse({
        ok: true,
        purgedNotes,
        mediaDeleted,
      });
    }

    throw new AppError('invalid-argument', `Unsupported maintenance job: ${job}`);
  } catch (err) {
    return errorResponse(err);
  }
}
