import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupabaseTestDb } from './pglite_supabase_harness.mjs';

const OWNER = '11111111-1111-4111-8111-111111111111';
const EDITOR = '22222222-2222-4222-8222-222222222222';
const VIEWER = '33333333-3333-4333-8333-333333333333';
const RECIPIENT = '44444444-4444-4444-8444-444444444444';
const STRANGER = '55555555-5555-4555-8555-555555555555';

async function seedUsers(ctx) {
  await ctx.createAuthUser({ id: OWNER, email: 'owner@example.com', name: 'Owner User', legacyFirebaseUid: 'fb_owner_123' });
  await ctx.createAuthUser({ id: EDITOR, email: 'editor@example.com', name: 'Editor User' });
  await ctx.createAuthUser({ id: VIEWER, email: 'viewer@example.com', name: 'Viewer User' });
  await ctx.createAuthUser({ id: RECIPIENT, email: 'recipient@example.com', name: 'Recipient User' });
  await ctx.createAuthUser({ id: STRANGER, email: 'stranger@example.com', name: 'Stranger User' });
}

test('auth bootstrap, profile email-enumeration guard, and peer profile RPC', async () => {
  const ctx = await createSupabaseTestDb();
  await seedUsers(ctx);

  // Trigger created profile and default settings for OWNER
  const ownProfile = await ctx.asUser(OWNER, (tx) =>
    tx.query(`SELECT id, email, name, legacy_firebase_uid FROM public.profiles`),
  );
  assert.equal(ownProfile.rows.length, 1);
  assert.equal(ownProfile.rows[0].email, 'owner@example.com');
  assert.equal(ownProfile.rows[0].legacy_firebase_uid, null);

  // Cannot modify protected identity columns directly
  await assert.rejects(() =>
    ctx.asUser(OWNER, (tx) =>
      tx.query(`UPDATE public.profiles SET email = 'spoof@example.com' WHERE id = $1`, [OWNER]),
    ),
  );

  // Stranger cannot scrape profiles via get_peer_profile
  const strangerLookup = await ctx.asUser(STRANGER, (tx) =>
    tx.query(`SELECT public.get_peer_profile($1) AS p`, [OWNER]),
  );
  assert.equal(strangerLookup.rows[0].p, null);

  // Connected peers CAN resolve display profile without exposing email or legacy UID
  await ctx.asService((tx) =>
    tx.query(
      `INSERT INTO public.connection_requests (connection_id, from_user_id, from_name, from_email, to_user_id, to_name, to_email, status)
       VALUES ('conn_1', $1, 'Owner', 'owner@example.com', $2, 'Editor', 'editor@example.com', 'accepted')`,
      [OWNER, EDITOR],
    ),
  );
  const peerLookup = await ctx.asUser(EDITOR, (tx) =>
    tx.query(`SELECT public.get_peer_profile($1) AS p`, [OWNER]),
  );
  assert.equal(peerLookup.rows[0].p.name, 'Owner User');
  assert.equal(peerLookup.rows[0].p.email, undefined);

  await ctx.db.close();
});

test('owner, editor, viewer, pending recipient, and stranger note RLS + soft-delete & revocation', async () => {
  const ctx = await createSupabaseTestDb();
  await seedUsers(ctx);

  // Owner creates note preserving arbitrary string ID (e.g. legacy Firestore 20-char ID)
  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `INSERT INTO public.notes (note_id, user_id, owner_name, owner_email, title, content, category, color)
       VALUES ('legacyNoteId00000001', $1, 'Owner User', 'owner@example.com', 'Roadmap', 'Initial body', 'Work', 'mint')`,
      [OWNER],
    ),
  );

  // Owner cannot self-grant live_member_ids via raw client PATCH
  await assert.rejects(() =>
    ctx.asUser(OWNER, (tx) =>
      tx.query(
        `UPDATE public.notes SET live_member_ids = ARRAY[$1]::uuid[] WHERE note_id = 'legacyNoteId00000001'`,
        [EDITOR],
      ),
    ),
  );

  // Server grants EDITOR='edit', VIEWER='view', RECIPIENT=pending share
  await ctx.asService((tx) =>
    tx.query(
      `UPDATE public.notes
          SET live_member_ids = ARRAY[$1::uuid, $2::uuid],
              live_roles = jsonb_build_object($1::text, 'edit', $2::text, 'view'),
              pending_shared_with_user_ids = ARRAY[$3::uuid]
        WHERE note_id = 'legacyNoteId00000001'`,
      [EDITOR, VIEWER, RECIPIENT],
    ),
  );

  // Stranger sees 0 rows
  const strangerRows = await ctx.asUser(STRANGER, (tx) =>
    tx.query(`SELECT note_id FROM public.notes`),
  );
  assert.equal(strangerRows.rows.length, 0);

  // Viewer can read, cannot update or commit_note_revision
  const viewerRows = await ctx.asUser(VIEWER, (tx) =>
    tx.query(`SELECT note_id, title FROM public.notes WHERE note_id = 'legacyNoteId00000001'`),
  );
  assert.equal(viewerRows.rows.length, 1);
  await assert.rejects(() =>
    ctx.asUser(VIEWER, (tx) =>
      tx.query(
        `SELECT public.commit_note_revision('legacyNoteId00000001', 0, 'Hacked', 'Body', 'Work', 'mint', false, '[]'::jsonb)`,
      ),
    ),
  );

  // Editor cannot toggle owner's is_favorite or trash the note via raw UPDATE
  await assert.rejects(() =>
    ctx.asUser(EDITOR, (tx) =>
      tx.query(
        `UPDATE public.notes SET is_favorite = true, revision = 1 WHERE note_id = 'legacyNoteId00000001'`,
      ),
    ),
  );
  await assert.rejects(() =>
    ctx.asUser(EDITOR, (tx) =>
      tx.query(
        `UPDATE public.notes SET deleted_at = now(), revision = 1 WHERE note_id = 'legacyNoteId00000001'`,
      ),
    ),
  );

  // Pending recipient can read preview and decline ONLY themselves, cannot edit note
  const pendingRows = await ctx.asUser(RECIPIENT, (tx) =>
    tx.query(`SELECT note_id FROM public.notes WHERE note_id = 'legacyNoteId00000001'`),
  );
  assert.equal(pendingRows.rows.length, 1);
  await ctx.asUser(RECIPIENT, (tx) =>
    tx.query(`SELECT public.decline_note_share('legacyNoteId00000001')`),
  );
  const afterDecline = await ctx.asUser(RECIPIENT, (tx) =>
    tx.query(`SELECT note_id FROM public.notes WHERE note_id = 'legacyNoteId00000001'`),
  );
  assert.equal(afterDecline.rows.length, 0);

  // Soft-deleting hides note from EDITOR and VIEWER while keeping it visible to OWNER
  await ctx.asUser(OWNER, (tx) =>
    tx.query(`UPDATE public.notes SET deleted_at = now() WHERE note_id = 'legacyNoteId00000001'`),
  );
  assert.equal(
    (await ctx.asUser(EDITOR, (tx) => tx.query(`SELECT note_id FROM public.notes`))).rows.length,
    0,
  );
  assert.equal(
    (await ctx.asUser(VIEWER, (tx) => tx.query(`SELECT note_id FROM public.notes`))).rows.length,
    0,
  );
  assert.equal(
    (await ctx.asUser(OWNER, (tx) => tx.query(`SELECT note_id FROM public.notes`))).rows.length,
    1,
  );

  // Restore makes it visible to live collaborators again
  await ctx.asUser(OWNER, (tx) =>
    tx.query(`UPDATE public.notes SET deleted_at = NULL WHERE note_id = 'legacyNoteId00000001'`),
  );
  assert.equal(
    (await ctx.asUser(EDITOR, (tx) => tx.query(`SELECT note_id FROM public.notes`))).rows.length,
    1,
  );

  // Revoking EDITOR immediately blocks access
  await ctx.asService((tx) =>
    tx.query(
      `UPDATE public.notes
          SET live_member_ids = ARRAY[$1::uuid],
              live_roles = jsonb_build_object($1::text, 'view')
        WHERE note_id = 'legacyNoteId00000001'`,
      [VIEWER],
    ),
  );
  assert.equal(
    (await ctx.asUser(EDITOR, (tx) => tx.query(`SELECT note_id FROM public.notes`))).rows.length,
    0,
  );

  await ctx.db.close();
});

test('commit_note_revision CAS concurrency and 5-minute activity notification deduplication', async () => {
  const ctx = await createSupabaseTestDb();
  await seedUsers(ctx);

  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `INSERT INTO public.notes (note_id, user_id, title, content, category, color, is_favorite)
       VALUES ('collab_note', $1, 'Spec', 'Hello', 'Projects', 'blue', true)`,
      [OWNER],
    ),
  );
  await ctx.asService((tx) =>
    tx.query(
      `UPDATE public.notes
          SET live_member_ids = ARRAY[$1::uuid, $2::uuid],
              live_roles = jsonb_build_object($1::text, 'edit', $2::text, 'view')
        WHERE note_id = 'collab_note'`,
      [EDITOR, VIEWER],
    ),
  );

  // Editor commits against revision 0 -> revision becomes 1; owner's is_favorite stays true even if editor passes false
  const firstCommit = await ctx.asUser(EDITOR, (tx) =>
    tx.query(
      `SELECT public.commit_note_revision('collab_note', 0, 'Spec', 'Hello from editor', 'Projects', 'blue', false, '[]'::jsonb) AS res`,
    ),
  );
  assert.equal(firstCommit.rows[0].res.committed, true);
  assert.equal(firstCommit.rows[0].res.note.revision, 1);
  assert.equal(firstCommit.rows[0].res.note.is_favorite, true);
  assert.equal(firstCommit.rows[0].res.note.last_edited_by, EDITOR);

  // Concurrent stale commit from Owner expecting revision 0 returns { committed: false, remote } without overwriting!
  const staleCommit = await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `SELECT public.commit_note_revision('collab_note', 0, 'Spec', 'Owner stale write', 'Projects', 'blue', true, '[]'::jsonb) AS res`,
    ),
  );
  assert.equal(staleCommit.rows[0].res.committed, false);
  assert.equal(staleCommit.rows[0].res.remote.revision, 1);
  assert.equal(staleCommit.rows[0].res.remote.content, 'Hello from editor');

  // Second edit by EDITOR within same 5-minute window commits cleanly (revision 2) WITHOUT duplicating notifications!
  const secondEditorCommit = await ctx.asUser(EDITOR, (tx) =>
    tx.query(
      `SELECT public.commit_note_revision('collab_note', 1, 'Spec', 'Hello from editor v2', 'Projects', 'blue', false, '[]'::jsonb) AS res`,
    ),
  );
  assert.equal(secondEditorCommit.rows[0].res.committed, true);
  assert.equal(secondEditorCommit.rows[0].res.note.revision, 2);

  // Owner and Viewer each received exactly 1 'live' notification; Editor received 0
  const ownerNotifs = await ctx.asUser(OWNER, (tx) =>
    tx.query(`SELECT type, title FROM public.notifications WHERE type = 'live'`),
  );
  const viewerNotifs = await ctx.asUser(VIEWER, (tx) =>
    tx.query(`SELECT type, title FROM public.notifications WHERE type = 'live'`),
  );
  const editorNotifs = await ctx.asUser(EDITOR, (tx) =>
    tx.query(`SELECT type, title FROM public.notifications WHERE type = 'live'`),
  );
  assert.equal(ownerNotifs.rows.length, 1);
  assert.equal(viewerNotifs.rows.length, 1);
  assert.equal(editorNotifs.rows.length, 0);

  await ctx.db.close();
});

test('private favorites, atomic settings merge, AI chats/feedback guards, and connection accept trigger', async () => {
  const ctx = await createSupabaseTestDb();
  await seedUsers(ctx);

  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `INSERT INTO public.notes (note_id, user_id, title, content) VALUES ('n1', $1, 'Shared', 'Body')`,
      [OWNER],
    ),
  );
  await ctx.asService((tx) =>
    tx.query(
      `UPDATE public.notes SET live_member_ids = ARRAY[$1::uuid], live_roles = jsonb_build_object($1::text, 'view') WHERE note_id = 'n1'`,
      [VIEWER],
    ),
  );

  // Viewer stars shared note privately; Owner cannot see Viewer's favorite; Stranger cannot star unauthorized note
  await ctx.asUser(VIEWER, (tx) =>
    tx.query(`INSERT INTO public.user_favorites (user_id, note_id) VALUES ($1, 'n1')`, [VIEWER]),
  );
  assert.equal(
    (await ctx.asUser(OWNER, (tx) => tx.query(`SELECT * FROM public.user_favorites`))).rows.length,
    0,
  );
  await assert.rejects(() =>
    ctx.asUser(STRANGER, (tx) =>
      tx.query(`INSERT INTO public.user_favorites (user_id, note_id) VALUES ($1, 'n1')`, [STRANGER]),
    ),
  );

  // Multi-device partial settings merge preserves unrelated keys
  await ctx.asUser(OWNER, (tx) =>
    tx.query(`SELECT public.merge_user_settings('{"theme":"dark","appLock":true}'::jsonb, 420)`),
  );
  const merged = await ctx.asUser(OWNER, (tx) =>
    tx.query(`SELECT public.merge_user_settings('{"textSize":19}'::jsonb) AS prefs`),
  );
  assert.equal(merged.rows[0].prefs.theme, 'dark');
  assert.equal(merged.rows[0].prefs.appLock, true);
  assert.equal(merged.rows[0].prefs.textSize, 19);

  // AI messages: owner can update feedback (`fb`), cannot tamper with `blocks` or `sources`
  await ctx.asUser(OWNER, (tx) =>
    tx.query(`INSERT INTO public.ai_chats (user_id, chat_id, title) VALUES ($1, 'c1', 'Chat 1')`, [OWNER]),
  );
  await ctx.asService((tx) =>
    tx.query(
      `INSERT INTO public.ai_messages (id, user_id, chat_id, role, blocks, sources)
       VALUES ('m1', $1, 'c1', 'ai', '[{"t":"p","x":"Answer"}]'::jsonb, '["n1"]'::jsonb)`,
      [OWNER],
    ),
  );
  await ctx.asUser(OWNER, (tx) =>
    tx.query(`UPDATE public.ai_messages SET fb = 'up' WHERE id = 'm1'`),
  );
  await assert.rejects(() =>
    ctx.asUser(OWNER, (tx) =>
      tx.query(`UPDATE public.ai_messages SET sources = '["forged"]'::jsonb WHERE id = 'm1'`),
    ),
  );

  // Connection acceptance: only recipient (`to_user_id`) can accept, which triggers notification for sender
  await ctx.asService((tx) =>
    tx.query(
      `INSERT INTO public.connection_requests (connection_id, from_user_id, from_name, from_email, to_user_id, to_name, to_email, status)
       VALUES ('req_1', $1, 'Owner', 'owner@example.com', $2, 'Recipient', 'recipient@example.com', 'pending')`,
      [OWNER, RECIPIENT],
    ),
  );
  // Sender cannot accept their own outbound request
  await assert.rejects(async () => {
    const res = await ctx.asUser(OWNER, (tx) =>
      tx.query(`UPDATE public.connection_requests SET status = 'accepted' WHERE connection_id = 'req_1' RETURNING connection_id`),
    );
    if (res.rows.length === 0) throw new Error('RLS blocked update');
  });
  // Recipient accepts -> sender receives notification
  const accepted = await ctx.asUser(RECIPIENT, (tx) =>
    tx.query(`UPDATE public.connection_requests SET status = 'accepted' WHERE connection_id = 'req_1' RETURNING status`),
  );
  assert.equal(accepted.rows[0].status, 'accepted');
  const senderNotifs = await ctx.asUser(OWNER, (tx) =>
    tx.query(`SELECT title FROM public.notifications WHERE type = 'request'`),
  );
  assert.equal(senderNotifs.rows.length, 1);
  assert.equal(senderNotifs.rows[0].title, 'Connection accepted');

  await ctx.db.close();
});

test('private storage buckets (`public = false`) and storage.objects RLS for avatars and note-media', async () => {
  const ctx = await createSupabaseTestDb();
  await seedUsers(ctx);

  // Verify both buckets exist and are strictly private (`public = false`)
  const buckets = await ctx.db.query(`SELECT id, public FROM storage.buckets ORDER BY id`);
  assert.deepEqual(buckets.rows, [
    { id: 'avatars', public: false },
    { id: 'note-media', public: false },
  ]);

  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `INSERT INTO public.notes (note_id, user_id, title, content) VALUES ('media_note', $1, 'Media', 'Body')`,
      [OWNER],
    ),
  );
  await ctx.asService((tx) =>
    tx.query(
      `UPDATE public.notes
          SET live_member_ids = ARRAY[$1::uuid, $2::uuid],
              live_roles = jsonb_build_object($1::text, 'edit', $2::text, 'view')
        WHERE note_id = 'media_note'`,
      [EDITOR, VIEWER],
    ),
  );

  // Owner and Editor can upload into their own uploader folder for `media_note`
  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('note-media', $1, $2)`,
      [`users/${OWNER}/notes/media_note/1_photo.jpg`, OWNER],
    ),
  );
  await ctx.asUser(EDITOR, (tx) =>
    tx.query(
      `INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('note-media', $1, $2)`,
      [`users/${EDITOR}/notes/media_note/2_voice.m4a`, EDITOR],
    ),
  );

  // Editor CANNOT upload spoofing Owner's uploader prefix
  await assert.rejects(() =>
    ctx.asUser(EDITOR, (tx) =>
      tx.query(
        `INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('note-media', $1, $2)`,
        [`users/${OWNER}/notes/media_note/spoof.jpg`, EDITOR],
      ),
    ),
  );

  // Viewer can read both attachments, CANNOT upload
  const viewerObjects = await ctx.asUser(VIEWER, (tx) =>
    tx.query(`SELECT name FROM storage.objects WHERE bucket_id = 'note-media'`),
  );
  assert.equal(viewerObjects.rows.length, 2);
  await assert.rejects(() =>
    ctx.asUser(VIEWER, (tx) =>
      tx.query(
        `INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('note-media', $1, $2)`,
        [`users/${VIEWER}/notes/media_note/nope.jpg`, VIEWER],
      ),
    ),
  );

  // Stranger sees 0 storage objects
  const strangerObjects = await ctx.asUser(STRANGER, (tx) =>
    tx.query(`SELECT name FROM storage.objects WHERE bucket_id = 'note-media'`),
  );
  assert.equal(strangerObjects.rows.length, 0);

  // Revoking Viewer immediately blocks reading private note-media objects
  await ctx.asService((tx) =>
    tx.query(
      `UPDATE public.notes SET live_member_ids = ARRAY[$1::uuid], live_roles = jsonb_build_object($1::text, 'edit') WHERE note_id = 'media_note'`,
      [EDITOR],
    ),
  );
  const revokedObjects = await ctx.asUser(VIEWER, (tx) =>
    tx.query(`SELECT name FROM storage.objects WHERE bucket_id = 'note-media'`),
  );
  assert.equal(revokedObjects.rows.length, 0);

  await ctx.db.close();
});

test('commit_note_revision persists calendar created_at edits and triggers guard profile insert & note updated_at', async () => {
  const ctx = await createSupabaseTestDb();
  await seedUsers(ctx);

  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `INSERT INTO public.notes (note_id, user_id, title, content, created_at)
       VALUES ('dated_note_1', $1, 'Journal', 'Entry', '2026-10-01T00:00:00Z')`,
      [OWNER],
    ),
  );

  // Calendar date edit via commit_note_revision updates created_at
  const commitDated = await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `SELECT public.commit_note_revision('dated_note_1', 0, 'Journal', 'Updated entry', 'Personal', 'blue', false, '[]'::jsonb, '2026-10-15T12:00:00Z'::timestamptz) AS res`,
    ),
  );
  assert.equal(commitDated.rows[0].res.committed, true);
  assert.ok(String(commitDated.rows[0].res.note.created_at).startsWith('2026-10-15'));

  // Client cannot spoof ancient updated_at via direct PATCH
  await ctx.asUser(OWNER, (tx) =>
    tx.query(
      `UPDATE public.notes SET title = 'Journal 2', updated_at = '2001-01-01T00:00:00Z' WHERE note_id = 'dated_note_1'`,
    ),
  );
  const afterPatch = await ctx.asUser(OWNER, (tx) =>
    tx.query(`SELECT updated_at FROM public.notes WHERE note_id = 'dated_note_1'`),
  );
  assert.ok(!String(afterPatch.rows[0].updated_at).startsWith('2001-01-01'));

  // Client cannot insert profile with legacy_firebase_uid or mismatched email
  await ctx.asService((tx) =>
    tx.query(`DELETE FROM public.profiles WHERE id = $1`, [STRANGER]),
  );
  await assert.rejects(() =>
    ctx.asUser(STRANGER, (tx) =>
      tx.query(
        `INSERT INTO public.profiles (id, email, name, legacy_firebase_uid)
         VALUES ($1, 'stranger@example.com', 'Stranger', 'spoof_fb_uid')`,
        [STRANGER],
      ),
    ),
  );
  await assert.rejects(() =>
    ctx.asUser(STRANGER, (tx) =>
      tx.query(
        `INSERT INTO public.profiles (id, email, name)
         VALUES ($1, 'victim@example.com', 'Stranger')`,
        [STRANGER],
      ),
    ),
  );

  await ctx.db.close();
});
