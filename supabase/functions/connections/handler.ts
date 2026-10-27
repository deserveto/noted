import { requireAuthenticatedUser, type VerifyBearerToken } from '../_shared/auth.ts';
import {
  AppError,
  errorResponse,
  handleCorsPreflight,
  jsonResponse,
} from '../_shared/cors.ts';
import {
  sendResendEmail,
  type EmailEnv,
} from '../_shared/email.ts';
import {
  deterministicPairId,
  escapeHtml,
  isValidEmailAddress,
  isValidUuid,
  sha256Hex,
} from '../_shared/policy.ts';

export interface ConnectionRow {
  connection_id: string;
  from_user_id: string;
  from_name: string;
  from_email: string;
  to_user_id: string;
  to_name: string;
  to_email: string;
  status: 'pending' | 'accepted' | 'rejected';
  created_at: string;
  updated_at: string;
}

export interface ConnectionsStore {
  checkRateLimit(uid: string, op: string, limit: number): Promise<boolean>;
  findProfileByEmail(
    email: string,
  ): Promise<{ id: string; email: string; name: string } | null>;
  getProfile(
    uid: string,
  ): Promise<{ id: string; email: string; name: string } | null>;
  getUserSettings(
    uid: string,
  ): Promise<{ preferences: Record<string, unknown>; timezoneOffsetMinutes: number }>;
  listAcceptedPeerIds(uid: string): Promise<Set<string>>;
  getConnection(connectionId: string): Promise<ConnectionRow | null>;
  upsertConnection(row: Record<string, unknown>): Promise<void>;
  touchConnection(connectionId: string): Promise<void>;
  upsertInvitation(uid: string, emailHash: string, email: string): Promise<void>;
  insertNotification(params: {
    userId: string;
    type: 'request';
    title: string;
    body: string;
    actorId: string;
    actorName: string;
    emailDispatched: boolean;
  }): Promise<string>;
}

export interface ConnectionsDeps {
  verifyToken: VerifyBearerToken;
  store: ConnectionsStore;
  env: EmailEnv;
  fetchImpl?: typeof fetch;
}

export function createSupabaseConnectionsStore(admin: any): ConnectionsStore {
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
    async findProfileByEmail(email) {
      const normalized = email.trim().toLowerCase();
      const { data } = await admin
        .from('profiles')
        .select('id, email, name')
        .eq('email', normalized)
        .limit(1)
        .maybeSingle();
      return data ?? null;
    },
    async getProfile(uid) {
      const { data } = await admin
        .from('profiles')
        .select('id, email, name')
        .eq('id', uid)
        .maybeSingle();
      return data ?? null;
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
    async listAcceptedPeerIds(uid) {
      if (!isValidUuid(uid)) return new Set<string>();
      const { data } = await admin
        .from('connection_requests')
        .select('from_user_id, to_user_id')
        .eq('status', 'accepted')
        .or(`from_user_id.eq.${uid},to_user_id.eq.${uid}`);
      const peers = new Set<string>();
      for (const row of data ?? []) {
        peers.add(row.from_user_id === uid ? row.to_user_id : row.from_user_id);
      }
      return peers;
    },
    async getConnection(connectionId) {
      const { data } = await admin
        .from('connection_requests')
        .select('*')
        .eq('connection_id', connectionId)
        .maybeSingle();
      return (data as ConnectionRow | null) ?? null;
    },
    async upsertConnection(row) {
      const { error } = await admin
        .from('connection_requests')
        .upsert(row, { onConflict: 'connection_id' });
      if (error) throw new AppError('already-exists', 'Connection request already exists.');
    },
    async touchConnection(connectionId) {
      await admin
        .from('connection_requests')
        .update({ updated_at: new Date().toISOString() })
        .eq('connection_id', connectionId);
    },
    async upsertInvitation(uid, emailHash, email) {
      await admin.from('user_invitations').upsert(
        {
          user_id: uid,
          email_hash: emailHash,
          email,
          sent_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,email_hash' },
      );
    },
    async insertNotification(params) {
      const id = crypto.randomUUID().replace(/-/g, '');
      const { error } = await admin.from('notifications').insert({
        id,
        user_id: params.userId,
        type: params.type,
        title: params.title,
        body: params.body,
        actor_id: params.actorId,
        actor_name: params.actorName,
        read: false,
        email_dispatched: params.emailDispatched,
        created_at: new Date().toISOString(),
      });
      if (error) throw new AppError('internal', error.message);
      return id;
    },
  };
}

async function enforceRequestPrivacy(
  store: ConnectionsStore,
  fromUid: string,
  targetUid: string,
) {
  const { preferences } = await store.getUserSettings(targetUid);
  const policy = preferences.requests ?? 'everyone';
  if (policy === 'nobody') {
    throw new AppError(
      'permission-denied',
      'This person is not accepting connection requests.',
    );
  }
  if (policy === 'mutual') {
    const [mine, theirs] = await Promise.all([
      store.listAcceptedPeerIds(fromUid),
      store.listAcceptedPeerIds(targetUid),
    ]);
    const hasMutual = [...mine].some((peer) => theirs.has(peer));
    if (!hasMutual) {
      throw new AppError(
        'permission-denied',
        'This person only accepts requests from mutual connections.',
      );
    }
  }
}

export async function handleConnectionsRequest(
  req: Request,
  deps: ConnectionsDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    const caller = await requireAuthenticatedUser(req, deps.verifyToken);
    const payload = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const action = String(payload.action ?? '');

    if (action === 'requestConnection') {
      const allowed = await deps.store.checkRateLimit(caller.uid, 'requestConnection', 20);
      if (!allowed) {
        throw new AppError(
          'resource-exhausted',
          'Too many connection requests. Try again later.',
        );
      }

      const email = String(payload.email ?? '')
        .trim()
        .toLowerCase();
      if (!isValidEmailAddress(email)) {
        throw new AppError('invalid-argument', 'Enter a valid email address.');
      }

      const target = await deps.store.findProfileByEmail(email);
      if (!target) {
        throw new AppError('not-found', 'No user found with that email.');
      }
      if (target.id === caller.uid) {
        throw new AppError('invalid-argument', 'You cannot connect with yourself.');
      }

      await enforceRequestPrivacy(deps.store, caller.uid, target.id);

      const id = await deterministicPairId(caller.uid, target.id);
      const existing = await deps.store.getConnection(id);
      if (existing && existing.status !== 'rejected') {
        throw new AppError('already-exists', 'Connection request already exists.');
      }

      const me = await deps.store.getProfile(caller.uid);
      const now = new Date().toISOString();
      await deps.store.upsertConnection({
        connection_id: id,
        from_user_id: caller.uid,
        from_name: me?.name ?? '',
        from_email: me?.email ?? caller.email ?? '',
        to_user_id: target.id,
        to_name: target.name ?? '',
        to_email: email,
        status: 'pending',
        created_at: now,
        updated_at: now,
      });

      const { preferences } = await deps.store.getUserSettings(
        target.id,
      );
      if (preferences.nRequests !== false) {
        const actorName = me?.name || caller.email || 'Someone';
        const title = `${actorName} wants to connect`;
        const body = 'Open Collaborators to accept or decline.';
        const notifId = await deps.store.insertNotification({
          userId: target.id,
          type: 'request',
          title,
          body,
          actorId: caller.uid,
          actorName,
          emailDispatched: false,
        });


      }

      return jsonResponse({ ok: true, id });
    }

    if (action === 'resendConnectionRequest') {
      const allowed = await deps.store.checkRateLimit(caller.uid, 'resendConnection', 10);
      if (!allowed) {
        throw new AppError(
          'resource-exhausted',
          'Too many reminders. Try again later.',
        );
      }

      const connectionId = String(payload.connectionId ?? '').trim();
      if (!connectionId) {
        throw new AppError('invalid-argument', 'Connection ID is required.');
      }

      const conn = await deps.store.getConnection(connectionId);
      if (!conn || conn.from_user_id !== caller.uid || conn.status !== 'pending') {
        throw new AppError('permission-denied', 'Cannot resend this request.');
      }

      await enforceRequestPrivacy(deps.store, caller.uid, conn.to_user_id);
      await deps.store.touchConnection(connectionId);

      const { preferences } = await deps.store.getUserSettings(
        conn.to_user_id,
      );
      if (preferences.nRequests !== false) {
        const actorName = conn.from_name || conn.from_email || 'Someone';
        const title = 'Connection request reminder';
        const body = `${actorName} wants to collaborate in Noted.`;
        const notifId = await deps.store.insertNotification({
          userId: conn.to_user_id,
          type: 'request',
          title,
          body,
          actorId: caller.uid,
          actorName,
          emailDispatched: false,
        });


      }

      return jsonResponse({ ok: true });
    }

    if (action === 'inviteByEmail') {
      const allowed = await deps.store.checkRateLimit(caller.uid, 'inviteByEmail', 10);
      if (!allowed) {
        throw new AppError(
          'resource-exhausted',
          'Too many invitations. Try again later.',
        );
      }

      const email = String(payload.email ?? '')
        .trim()
        .toLowerCase();
      if (!isValidEmailAddress(email)) {
        throw new AppError('invalid-argument', 'Enter a valid email address.');
      }

      // Existing accounts receive no signup invitation; return the same response
      // regardless of their privacy settings to avoid disclosing registration.
      if (await deps.store.findProfileByEmail(email)) return jsonResponse({ ok: true });

      const appUrl = deps.env.appUrl?.trim().replace(/\/+$/, '') ?? '';
      if (!appUrl.startsWith('https://')) {
        throw new AppError(
          'failed-precondition',
          'Set a secure NOTED_APP_URL before sending invitations.',
        );
      }

      const me = await deps.store.getProfile(caller.uid);
      const sender = me?.name || caller.email || 'A collaborator';
      const day = new Date().toISOString().slice(0, 10);
      const emailHash = await sha256Hex(email);

      await sendResendEmail({
        fetchImpl: deps.fetchImpl,
        env: deps.env,
        to: email,
        subject: `${sender} invited you to Noted`,
        html:
          `<div style="font-family:Georgia,serif;color:#1C1917;line-height:1.6;max-width:480px">` +
          `<p style="font-size:18px;margin:0 0 8px"><strong>${escapeHtml(sender)} invited you to Noted</strong></p>` +
          `<p style="color:#57534E;margin:0 0 18px">Create your account with ${escapeHtml(email)} to share and edit notes together.</p>` +
          `<p><a href="${escapeHtml(appUrl)}" style="color:#2D6A4F;font-weight:600">Open Noted</a></p></div>`,
        idempotencyKey: `invite-${caller.uid}-${emailHash.slice(0, 24)}-${day}`,
        requireConfigured: true,
      });

      await deps.store.upsertInvitation(caller.uid, emailHash, email);
      return jsonResponse({ ok: true });
    }

    throw new AppError('invalid-argument', `Unsupported connections action: ${action}`);
  } catch (err) {
    return errorResponse(err);
  }
}
