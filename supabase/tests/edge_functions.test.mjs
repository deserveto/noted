import test from 'node:test';
import assert from 'node:assert/strict';

import { handleNotedAiRequest } from '../functions/noted-ai/handler.ts';
import { handleNoteSharingRequest } from '../functions/note-sharing/handler.ts';
import { handleConnectionsRequest } from '../functions/connections/handler.ts';
import { handleAccountRequest } from '../functions/account/handler.ts';
import { handleScheduledMaintenanceRequest } from '../functions/scheduled-maintenance/handler.ts';

const ALICE = { uid: '11111111-1111-4111-8111-111111111111', email: 'alice@example.com' };
const BOB = { uid: '22222222-2222-4222-8222-222222222222', email: 'bob@example.com' };
const MUTUAL = { uid: '33333333-3333-4333-8333-333333333333', email: 'mutual@example.com' };

const verifyToken = async (jwt) => {
  if (jwt === 'token-alice') return ALICE;
  if (jwt === 'token-bob') return BOB;
  return null;
};

function postReq(body, token = 'token-alice', extraHeaders = {}) {
  return new Request('https://project.supabase.co/functions/v1/fn', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });
}

test('noted-ai enforces auth, OpenRouter 400 json_object fallback, source subset validation, and cancellation', async () => {
  const requests = new Map();
  const savedExchanges = [];
  let accessibleNotes = [
    {
      id: 'note_allowed',
      title: 'Q4 Launch Plan',
      content: JSON.stringify({
        notedDocument: 1,
        ops: [{ insert: 'Ship Supabase migration in October.\n' }],
      }),
      category: 'Work',
      isFavorite: true,
      updatedAt: '2026-10-26T00:00:00Z',
    },
  ];

  const store = {
    async checkRateLimit() { return true; },
    async getSettings() { return { aiEnabled: true, aiHistory: true }; },
    async getAiRequest(uid, reqId) { return requests.get(`${uid}:${reqId}`) ?? null; },
    async upsertAiRequest(uid, reqId, patch) {
      const prev = requests.get(`${uid}:${reqId}`) ?? {};
      requests.set(`${uid}:${reqId}`, { ...prev, ...patch });
    },
    async clearHistory() { savedExchanges.length = 0; },
    async listAccessibleNotes() { return accessibleNotes; },
    async listRecentChatMessages() { return []; },
    async commitAiExchange(ex) {
      savedExchanges.push(ex);
      return 'msg_1';
    },
  };

  // 1. Unauthenticated rejected
  const unauthRes = await handleNotedAiRequest(postReq({ prompt: 'Hi' }, ''), {
    verifyToken,
    store,
    env: { aiApiKey: 'sk-or-test' },
  });
  assert.equal(unauthRes.status, 401);

  // 2. OpenRouter 400 fallback + fenced JSON + unauthorized source stripping
  let openRouterCalls = 0;
  let capturedUrl = '';
  let capturedModel = '';
  const fakeFetch = async (url, init) => {
    openRouterCalls++;
    capturedUrl = String(url);
    const parsedBody = JSON.parse(String(init.body));
    capturedModel = parsedBody.model;
    if (openRouterCalls === 1 && parsedBody.response_format) {
      return new Response('json_object unsupported by free model', { status: 400 });
    }
    return new Response(
      JSON.stringify({
        choices: [
          {
            message: {
              content:
                '```json\n{"intent":"summary","blocks":[{"t":"p","x":"Supabase launches in October."}],"sources":["note_allowed","forged_secret_note"]}\n```',
            },
          },
        ],
      }),
      { status: 200 },
    );
  };

  const okRes = await handleNotedAiRequest(
    postReq({
      action: 'ask',
      prompt: 'Summarize launch plan',
      scope: { kind: 'all' },
      chatId: 'chat_1',
      requestId: 'req_1',
    }),
    {
      verifyToken,
      store,
      fetchImpl: fakeFetch,
      env: {
        aiBaseUrl: 'https://openrouter.ai/api/v1',
        aiModel: 'openrouter/free',
        aiApiKey: 'sk-or-test',
        appUrl: 'https://noted.example',
      },
    },
  );
  assert.equal(okRes.status, 200);
  assert.equal(openRouterCalls, 2);
  assert.equal(capturedUrl, 'https://openrouter.ai/api/v1/chat/completions');
  assert.equal(capturedModel, 'openrouter/free');
  const data = await okRes.json();
  assert.deepEqual(data.sources, ['note_allowed']); // Hallucinated note stripped!
  assert.equal(savedExchanges.length, 1);

  // 3. Cancel aborts in-flight request and writes nothing
  const cancelFetch = async (_url, init) => {
    await handleNotedAiRequest(
      postReq({ action: 'cancel', requestId: 'req_cancel' }),
      { verifyToken, store, env: { aiApiKey: 'sk-or-test' } },
    );
    return new Promise((_resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(new Error('Aborted')));
      setTimeout(() => reject(new Error('Aborted')), 600);
    });
  };
  const cancelRes = await handleNotedAiRequest(
    postReq({ prompt: 'Long task', requestId: 'req_cancel' }),
    { verifyToken, store, fetchImpl: cancelFetch, env: { aiApiKey: 'sk-or-test' } },
  );
  assert.equal(cancelRes.status, 499);
  assert.equal((await cancelRes.json()).code, 'cancelled');
  assert.equal(savedExchanges.length, 1);
});

test('note-sharing copies private media independently and rolls back copied blobs on failure', async () => {
  const storageObjects = new Set([`users/${ALICE.uid}/notes/n_src/1_chart.png`, `users/${ALICE.uid}/notes/n_src/2_audio.m4a`]);
  let failOnSecondCopy = false;

  const storage = {
    from() {
      let copyCount = 0;
      return {
        async copy(fromPath, toPath) {
          copyCount++;
          if (!storageObjects.has(fromPath)) return { error: { message: 'missing' } };
          if (failOnSecondCopy && copyCount === 2) {
            return { error: { message: 'disk quota' } };
          }
          storageObjects.add(toPath);
          return { error: null };
        },
        async remove(paths) {
          for (const p of paths) storageObjects.delete(p);
          return { error: null };
        },
      };
    },
  };

  const notes = new Map([
    [
      'n_src',
      {
        note_id: 'n_src',
        user_id: ALICE.uid,
        owner_name: 'Alice',
        owner_email: ALICE.email,
        title: 'Strategy',
        content: `{"notedDocument":1,"ops":[{"insert":{"notedImage":"noted-media://note-media/users/${ALICE.uid}/notes/n_src/1_chart.png"}},{"insert":"\\n"}]}`,
        category: 'Work',
        color: 'mint',
        is_favorite: true,
        live_member_ids: [],
        live_roles: {},
        shared_with_user_ids: [BOB.uid],
        pending_shared_with_user_ids: [BOB.uid],
        source_owner_id: null,
        source_note_id: null,
        attachments: [
          {
            type: 'image',
            name: 'chart.png',
            path: `users/${ALICE.uid}/notes/n_src/1_chart.png`,
            url: `noted-media://note-media/users/${ALICE.uid}/notes/n_src/1_chart.png`,
          },
          {
            type: 'audio',
            name: 'audio.m4a',
            path: `users/${ALICE.uid}/notes/n_src/2_audio.m4a`,
            url: `noted-media://note-media/users/${ALICE.uid}/notes/n_src/2_audio.m4a`,
          },
        ],
        revision: 3,
        last_edited_by: ALICE.uid,
        deleted_at: null,
        created_at: '2026-10-26T00:00:00Z',
        updated_at: '2026-10-26T00:00:00Z',
      },
    ],
  ]);

  const store = {
    async checkRateLimit() { return true; },
    async getNote(id) { return notes.get(id) ?? null; },
    async updateNote(id, patch) { notes.set(id, { ...notes.get(id), ...patch }); },
    async acceptNoteCopy(id, uid, revision, row) {
      const note = notes.get(id);
      if (note.revision !== revision || !note.pending_shared_with_user_ids.includes(uid)) throw Error('conflict');
      notes.set(row.note_id, row);
      notes.set(id, { ...note, pending_shared_with_user_ids: note.pending_shared_with_user_ids.filter(value => value !== uid) });
    },
    async reserveCopyCleanup() {},
    async completeCopyCleanup() {},
    async duplicateNote(_noteId, _actorId, _revision, row) { notes.set(row.note_id, row); },
    async deleteNoteRow(id) { notes.delete(id); },
    async deletePresence() {},
    async hasAcceptedConnection() { return true; },
    async getUserSettings() { return { preferences: {}, timezoneOffsetMinutes: 0 }; },
    async getProfile(uid) {
      return uid === ALICE.uid
        ? { id: ALICE.uid, email: ALICE.email, name: 'Alice' }
        : { id: BOB.uid, email: BOB.email, name: 'Bob' };
    },
    async insertNotification() { return 'notif_1'; },
  };

  // 1. Failure on second attachment rolls back first copied object!
  failOnSecondCopy = true;
  const failRes = await handleNoteSharingRequest(
    postReq({ action: 'acceptNoteCopy', noteId: 'n_src' }, 'token-bob'),
    { verifyToken, store, storage, env: {} },
  );
  assert.equal(failRes.status, 412);
  assert.equal(storageObjects.size, 2); // Zero orphan objects left behind!

  // 2. Successful acceptNoteCopy creates independent storage paths & rewrites inline URI
  failOnSecondCopy = false;
  const okRes = await handleNoteSharingRequest(
    postReq({ action: 'acceptNoteCopy', noteId: 'n_src' }, 'token-bob'),
    { verifyToken, store, storage, env: {} },
  );
  assert.equal(okRes.status, 200);
  const { noteId: copyId } = await okRes.json();
  const copyRow = notes.get(copyId);
  assert.equal(copyRow.user_id, BOB.uid);
  assert.equal(copyRow.is_favorite, false);
  assert.equal(copyRow.source_owner_id, ALICE.uid);
  assert.equal(copyRow.source_note_id, 'n_src');
  assert.ok(copyRow.attachments[0].path.startsWith(`users/${BOB.uid}/notes/${copyId}/`));
  assert.ok(copyRow.content.includes(`noted-media://note-media/${copyRow.attachments[0].path}`));
  assert.ok(!copyRow.content.includes(`notes/n_src/`));
  assert.equal(notes.get('n_src').pending_shared_with_user_ids.length, 0);
});

test('connections enforces not-found, privacy (`nobody` vs `mutual`), and Resend invitation idempotency', async () => {
  let targetPrivacy = 'nobody';
  let alicePeers = new Set();
  const invitations = [];
  const sentEmails = [];

  const store = {
    async checkRateLimit() { return true; },
    async findProfileByEmail(email) {
      if (email === BOB.email) return { id: BOB.uid, email: BOB.email, name: 'Bob' };
      return null;
    },
    async getProfile(uid) {
      return { id: uid, email: uid === ALICE.uid ? ALICE.email : BOB.email, name: 'Alice' };
    },
    async getUserSettings(uid) {
      return {
        preferences: uid === BOB.uid ? { requests: targetPrivacy } : {},
        timezoneOffsetMinutes: 0,
      };
    },
    async listAcceptedPeerIds(uid) {
      return uid === ALICE.uid ? alicePeers : new Set([MUTUAL.uid]);
    },
    async getConnection() { return null; },
    async upsertConnection() {},
    async touchConnection() {},
    async upsertInvitation(uid, hash, email) { invitations.push({ uid, hash, email }); },
    async insertNotification() { return 'n1'; },
  };

  // Missing user -> 404 not-found (allows client to fall back to inviteByEmail)
  const missRes = await handleConnectionsRequest(
    postReq({ action: 'requestConnection', email: 'newperson@example.com' }),
    { verifyToken, store, env: {} },
  );
  assert.equal(missRes.status, 404);
  assert.equal((await missRes.json()).code, 'not-found');

  // Privacy 'nobody' -> 403 permission-denied (must NOT fall back to email!)
  const denyRes = await handleConnectionsRequest(
    postReq({ action: 'requestConnection', email: BOB.email }),
    { verifyToken, store, env: {} },
  );
  assert.equal(denyRes.status, 403);
  assert.equal((await denyRes.json()).code, 'permission-denied');

  // Privacy 'mutual' succeeds only once shared peer exists
  targetPrivacy = 'mutual';
  const noMutualRes = await handleConnectionsRequest(
    postReq({ action: 'requestConnection', email: BOB.email }),
    { verifyToken, store, env: {} },
  );
  assert.equal(noMutualRes.status, 403);

  alicePeers = new Set([MUTUAL.uid]);
  const mutualOkRes = await handleConnectionsRequest(
    postReq({ action: 'requestConnection', email: BOB.email }),
    { verifyToken, store, env: {} },
  );
  assert.equal(mutualOkRes.status, 200);

  // inviteByEmail sends Resend request with Idempotency-Key
  const inviteRes = await handleConnectionsRequest(
    postReq({ action: 'inviteByEmail', email: 'colleague@example.com' }),
    {
      verifyToken,
      store,
      env: {
        resendApiKey: 're_test',
        emailFrom: 'Noted <hi@noted.example>',
        appUrl: 'https://noted.example',
      },
      fetchImpl: async (url, init) => {
        sentEmails.push({ url: String(url), headers: init.headers });
        return new Response(JSON.stringify({ id: 'email_1' }), { status: 200 });
      },
    },
  );
  assert.equal(inviteRes.status, 200);
  assert.equal(invitations.length, 1);
  assert.equal(sentEmails.length, 1);
  assert.ok(sentEmails[0].headers['Idempotency-Key'].startsWith(`invite-${ALICE.uid}-`));
});

test('account verifies password before full deletion and scheduled-maintenance runs recap & 30d purge', async () => {
  let deletedAuthUid = null;
  const removedMedia = [];
  const storage = {
    from(bucket) {
      return {
        async copy() { return { error: null }; },
        async list() { return { data: bucket === 'avatars' ? [{ name: 'avatar.jpg' }] : [], error: null }; },
        async remove(paths) { removedMedia.push(...paths); return { error: null }; },
      };
    },
  };

  const accountStore = {
    async beginAccountDeletion() { return 0; },
    async ensureAccountInitialized() {},
    async listExportableNotes() {
      return [
        {
          id: 'n1',
          title: 'Plan',
          content: '{"notedDocument":1,"ops":[{"insert":"Bold","attributes":{"bold":true}}]}',
          category: 'Work',
          color: 'blue',
          isFavorite: true,
          createdAt: '2026-10-26T00:00:00Z',
          updatedAt: '2026-10-26T00:00:00Z',
        },
      ];
    },
    async listOwnedNotesForDeletion() {
      return [
        {
          note_id: 'n1',
          attachments: [{ path: `users/${ALICE.uid}/notes/n1/photo.jpg` }],
        },
      ];
    },
    async removeUserFromCollaborations() {},
    async deleteAllUserData() {},
    async deleteAuthUser(uid) { deletedAuthUid = uid; },
  };

  // Export data renders rich HTML cleanly
  const exportRes = await handleAccountRequest(
    postReq({ action: 'exportData' }),
    {
      verifyToken,
      verifyPassword: async () => false,
      store: accountStore,
      storage,
    },
  );
  const exported = await exportRes.json();
  assert.equal(exported.formatVersion, 1);
  assert.ok(exported.notes[0].html.includes('<strong>Bold</strong>'));

  // Wrong password blocks deleteAccount
  const badDel = await handleAccountRequest(
    postReq({ action: 'deleteAccount', currentPassword: 'wrong' }),
    {
      verifyToken,
      verifyPassword: async () => false,
      store: accountStore,
      storage,
    },
  );
  assert.equal(badDel.status, 403);
  assert.equal(deletedAuthUid, null);

  // Correct password wipes media + auth account
  const okDel = await handleAccountRequest(
    postReq({ action: 'deleteAccount', currentPassword: 'correct-password' }),
    {
      verifyToken,
      verifyPassword: async (_e, pw) => pw === 'correct-password',
      store: accountStore,
      storage,
    },
  );
  assert.equal(okDel.status, 200);
  assert.equal(deletedAuthUid, ALICE.uid);
  assert.ok(removedMedia.includes(`users/${ALICE.uid}/notes/n1/photo.jpg`));

  // Scheduled maintenance: Sunday 09:00 UTC recap + 30-day trash purge
  let purgedIds = [];
  const sundayNineAm = new Date('2026-10-25T09:15:00Z'); // 2026-10-25 is a Sunday!
  const cronRes = await handleScheduledMaintenanceRequest(
    postReq({ job: 'hourly' }, '', { 'x-cron-secret': 'sec_123' }),
    {
      cronSecret: 'sec_123',
      now: () => sundayNineAm,
      storage,
      env: {
        resendApiKey: 're_test',
        emailFrom: 'Noted <hi@noted.example>',
        appUrl: 'https://noted.example',
      },
      fetchImpl: async () => new Response('{}', { status: 200 }),
      store: {
        async listCopyCleanup() { return []; },
        async listCopySweeps() { return []; },
        async listPendingEmailNotifications() { return []; },
        async markNotificationEmailDispatched() {},
        async getRecipientContext() { return null; },
        async listRecapCandidates() {
          return [
            {
              userId: ALICE.uid,
              email: ALICE.email,
              preferences: { nRecap: true },
              timezoneOffsetMinutes: 0,
            },
          ];
        },
        async listOwnedNotesUpdatedSince() { return [{ title: 'Weekly wins' }]; },
        async listExpiredDeletedNotes() { return []; },
        async deleteNotesByIds() {},
        async cleanupEphemeralRows() {},
      },
    },
  );
  assert.equal(cronRes.status, 200);
  assert.equal((await cronRes.json()).recapsSent, 1);

  const purgeRes = await handleScheduledMaintenanceRequest(
    postReq({ job: 'purge' }, '', { 'x-cron-secret': 'sec_123' }),
    {
      cronSecret: 'sec_123',
      now: () => sundayNineAm,
      storage,
      env: {},
      store: {
        async listCopyCleanup() { return []; },
        async listCopySweeps() { return []; },
        async listPendingEmailNotifications() { return []; },
        async markNotificationEmailDispatched() {},
        async getRecipientContext() { return null; },
        async listRecapCandidates() { return []; },
        async listOwnedNotesUpdatedSince() { return []; },
        async listExpiredDeletedNotes() {
          return [
            {
              note_id: 'old_trashed',
              user_id: ALICE.uid,
              attachments: [{ path: `users/${ALICE.uid}/notes/old_trashed/pic.png` }],
            },
          ];
        },
        async claimNoteDeletion() { return { claimed: true, note: { attachments: [{ path: `users/${ALICE.uid}/notes/old_trashed/pic.png` }] } }; },
        async finalizeNoteDeletion(id) { purgedIds = [id]; return true; },
        async cleanupEphemeralRows() {},
      },
    },
  );
  assert.equal(purgeRes.status, 200);
  const purgeJson = await purgeRes.json();
  assert.equal(purgeJson.purgedNotes, 1);
  assert.equal(purgeJson.mediaDeleted, 1);
  assert.deepEqual(purgedIds, ['old_trashed']);
});

test('security & reliability guards: UUID validation, wildcard email rejection, duplicate title preservation, insertNote rollback, and email retry', async () => {
  const storageObjects = new Set([`users/${ALICE.uid}/notes/n_dup/1_img.png`]);
  const storage = {
    from() {
      return {
        async copy(fromPath, toPath) {
          if (!storageObjects.has(fromPath)) return { error: { message: 'missing' } };
          storageObjects.add(toPath);
          return { error: null };
        },
        async remove(paths) {
          for (const p of paths) storageObjects.delete(p);
          return { error: null };
        },
      };
    },
  };

  let failInsert = false;
  const insertedNotes = [];
  const noteStore = {
    async checkRateLimit() { return true; },
    async getNote(id) {
      return id === 'n_dup'
        ? {
            note_id: 'n_dup',
            user_id: ALICE.uid,
            owner_name: 'Alice',
            owner_email: ALICE.email,
            title: 'Spec',
            content: 'Body',
            category: 'Work',
            color: 'blue',
            is_favorite: false,
            live_member_ids: [],
            live_roles: {},
            shared_with_user_ids: [],
            pending_shared_with_user_ids: [],
            source_owner_id: null,
            source_note_id: null,
            attachments: [
              {
                type: 'image',
                name: 'img.png',
                path: `users/${ALICE.uid}/notes/n_dup/1_img.png`,
                url: `noted-media://note-media/users/${ALICE.uid}/notes/n_dup/1_img.png`,
              },
            ],
            revision: 1,
            last_edited_by: ALICE.uid,
            deleted_at: null,
            created_at: '2026-10-26T00:00:00Z',
            updated_at: '2026-10-26T00:00:00Z',
          }
        : null;
    },
    async updateNote() {},
    async reserveCopyCleanup() {},
    async completeCopyCleanup() {},
    async duplicateNote(_noteId, _actorId, _revision, row) {
      if (failInsert) throw new Error('db constraint failed');
      insertedNotes.push(row);
    },
    async deleteNoteRow() {},
    async deletePresence() {},
    async hasAcceptedConnection() { return true; },
    async getUserSettings() { return { preferences: {}, timezoneOffsetMinutes: 0 }; },
    async getProfile(uid) { return { id: uid, email: ALICE.email, name: 'Alice' }; },
    async insertNotification() { return 'n1'; },
  };

  // 1. Non-UUID targetUserId rejected before PostgREST .or()
  const badUuidRes = await handleNoteSharingRequest(
    postReq({
      action: 'setLiveRole',
      noteId: 'n_dup',
      targetUserId: 'not-a-uuid),status.eq.pending',
      role: 'edit',
    }),
    { verifyToken, store: noteStore, storage, env: {} },
  );
  assert.equal(badUuidRes.status, 400);

  // 2. insertNote failure rolls back copied storage objects
  failInsert = true;
  const rollbackRes = await handleNoteSharingRequest(
    postReq({ action: 'duplicateNote', noteId: 'n_dup' }),
    { verifyToken, store: noteStore, storage, env: {} },
  );
  assert.equal(rollbackRes.status, 500);
  assert.equal(storageObjects.size, 1); // Copied blob cleaned up!

  // 3. Explicit draft title is preserved without double '(Copy)'
  failInsert = false;
  const dupRes = await handleNoteSharingRequest(
    postReq({
      action: 'duplicateNote',
      noteId: 'n_dup',
      draft: {
        title: 'Spec (conflict copy)',
        content: 'Body',
        category: 'Work',
        color: 'blue',
        attachments: [],
      },
    }),
    { verifyToken, store: noteStore, storage, env: {} },
  );
  assert.equal(dupRes.status, 200);
  assert.equal(insertedNotes[0].title, 'Spec (conflict copy)');

  // 4. Wildcard '%' email rejected in connections
  const wildcardRes = await handleConnectionsRequest(
    postReq({ action: 'requestConnection', email: '%@example.com' }),
    {
      verifyToken,
      env: {},
      store: {
        async checkRateLimit() { return true; },
        async findProfileByEmail() { return null; },
        async getProfile() { return null; },
        async getUserSettings() { return { preferences: {}, timezoneOffsetMinutes: 0 }; },
        async listAcceptedPeerIds() { return new Set(); },
        async getConnection() { return null; },
        async upsertConnection() {},
        async touchConnection() {},
        async upsertInvitation() {},
        async insertNotification() { return 'n1'; },
      },
    },
  );
  assert.equal(wildcardRes.status, 400);

  // 5. Scheduled maintenance keeps email_dispatched=false on transient Resend 500 error
  const dispatchedIds = [];
  const maintRes = await handleScheduledMaintenanceRequest(
    postReq({ job: 'hourly' }, '', { 'x-cron-secret': 'sec_123' }),
    {
      cronSecret: 'sec_123',
      now: () => new Date('2026-10-26T14:00:00Z'),
      storage,
      env: {
        resendApiKey: 're_test',
        emailFrom: 'Noted <hi@noted.example>',
        appUrl: 'https://noted.example',
      },
      fetchImpl: async () => new Response('Provider outage', { status: 503 }),
      store: {
        async listCopyCleanup() { return []; },
        async listCopySweeps() { return []; },
        async listPendingEmailNotifications() {
          return [
            {
              id: 'notif_retry_1',
              user_id: ALICE.uid,
              type: 'live',
              title: 'Edited',
              body: 'Live update',
              note_id: 'n_dup',
            },
          ];
        },
        async markNotificationEmailDispatched(id) { dispatchedIds.push(id); },
        async getRecipientContext() {
          return { email: ALICE.email, preferences: { nLive: true }, timezoneOffsetMinutes: 0 };
        },
        async listRecapCandidates() { return []; },
        async listOwnedNotesUpdatedSince() { return []; },
        async listExpiredDeletedNotes() { return []; },
        async deleteNotesByIds() {},
        async cleanupEphemeralRows() {},
      },
    },
  );
  assert.equal(maintRes.status, 200);
  assert.deepEqual(dispatchedIds, []); // Left queued for retry!
});
