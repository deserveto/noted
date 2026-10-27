import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';

import { createSupabaseTestDb } from './pglite_supabase_harness.mjs';
import { firebaseUidToSupabaseUuid } from '../../tools/migration/id_mapping.mjs';
import {
  exportFirebaseBundle,
  parseArgs as parseExportArgs,
} from '../../tools/migration/export_firebase.mjs';
import {
  createPGliteExecutor,
  createSupabaseAdminExecutor,
  importBundleToExecutor,
} from '../../tools/migration/import_supabase.mjs';
import {
  createPGliteReader,
  createSupabaseAdminReader,
  validateMigratedBundle,
} from '../../tools/migration/validate_migration.mjs';
import { rollbackMigratedEntities } from '../../tools/migration/rollback_supabase.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const migrationToolsDir = path.resolve(__dirname, '..', '..', 'tools', 'migration');
const exportScript = path.join(migrationToolsDir, 'export_firebase.mjs');

// 28-character Firebase UIDs
const FB_OWNER_UID = 'k9L8m7N6p5Q4r3S2t1U0v9W8x7Y6';
const FB_EDITOR_UID = 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4';
const FB_VIEWER_UID = 'z9Y8x7W6v5U4t3S2r1Q0p9O8n7M6';
const FB_PENDING_UID = 'p1E2n3D4i5N6g7U8s9E0r1O2p3Q4';
const FB_CONN_UID = 'c1O2n3N4e5C6t7I8o9N0p1A2i3R4';

function buildSampleBundle() {
  const dummyAvatar = Buffer.from('fake-avatar-bytes');
  const dummyDiagram = Buffer.from('fake-diagram-bytes');
  const dummyPhoto = Buffer.from('fake-photo-bytes');

  return {
    manifest: {
      version: '1.0.0',
      projectId: 'superheromood-54691',
      exportedAt: '2026-10-26T12:00:00.000Z',
      counts: {
        authUsers: 5,
        users: 5,
        notes: 2,
        connectionRequests: 1,
        userSettings: 1,
        userFavorites: 1,
        userInvitations: 1,
        notifications: 1,
        aiChats: 1,
        aiMessages: 1,
        media: 3,
      },
    },
    auth: {
      exportNotice:
        'Firebase Auth passwords use a modified-scrypt algorithm with project-specific signer key. Passwords require reset.',
      passwordHashAlgorithm: 'firebase-scrypt',
      users: [
        {
          uid: FB_OWNER_UID,
          email: 'alice.owner@example.com',
          displayName: 'Alice Owner',
          emailVerified: true,
          metadata: { creationTime: '2026-01-01T00:00:00.000Z' },
        },
        {
          uid: FB_EDITOR_UID,
          email: 'bob.editor@example.com',
          displayName: 'Bob Editor',
          emailVerified: true,
          metadata: { creationTime: '2026-01-02T00:00:00.000Z' },
        },
        {
          uid: FB_VIEWER_UID,
          email: 'carol.viewer@example.com',
          displayName: 'Carol Viewer',
          emailVerified: true,
          metadata: { creationTime: '2026-01-03T00:00:00.000Z' },
        },
        {
          uid: FB_PENDING_UID,
          email: 'dave.pending@example.com',
          displayName: 'Dave Pending',
          emailVerified: true,
          metadata: { creationTime: '2026-01-04T00:00:00.000Z' },
        },
        {
          uid: FB_CONN_UID,
          email: 'eve.conn@example.com',
          displayName: 'Eve Connected',
          emailVerified: true,
          metadata: { creationTime: '2026-01-05T00:00:00.000Z' },
        },
      ],
    },
    firestore: {
      users: [
        {
          id: FB_OWNER_UID,
          name: 'Alice Owner',
          email: 'alice.owner@example.com',
          fieldOfStudy: 'Computer Science',
          avatarPath: `users/${FB_OWNER_UID}/avatar.png`,
          createdAt: '2026-01-01T00:00:00.000Z',
        },
        {
          id: FB_EDITOR_UID,
          name: 'Bob Editor',
          email: 'bob.editor@example.com',
          fieldOfStudy: 'Design',
          createdAt: '2026-01-02T00:00:00.000Z',
        },
        {
          id: FB_VIEWER_UID,
          name: 'Carol Viewer',
          email: 'carol.viewer@example.com',
          fieldOfStudy: 'Physics',
          createdAt: '2026-01-03T00:00:00.000Z',
        },
        {
          id: FB_PENDING_UID,
          name: 'Dave Pending',
          email: 'dave.pending@example.com',
          createdAt: '2026-01-04T00:00:00.000Z',
        },
        {
          id: FB_CONN_UID,
          name: 'Eve Connected',
          email: 'eve.conn@example.com',
          createdAt: '2026-01-05T00:00:00.000Z',
        },
      ],
      notes: [
        {
          id: 'firestore_note_quill_12345',
          userId: FB_OWNER_UID,
          ownerName: 'Alice Owner',
          ownerEmail: 'alice.owner@example.com',
          title: 'Quill Delta Sprint Architecture',
          content: JSON.stringify({
            notedDocument: 1,
            ops: [
              { insert: 'Sprint Architecture\n' },
              { attributes: { bold: true }, insert: 'Requirements:' },
              { insert: '\n- Complete migration\n' },
              {
                insert: {
                  image: `https://firebasestorage.googleapis.com/v0/b/superheromood-54691.appspot.com/o/users%2F${FB_OWNER_UID}%2Fnotes%2Ffirestore_note_quill_12345%2Fdiagram.png?alt=media`,
                },
              },
              { insert: '\nDeep link: noted://app/notes/firestore_note_quill_12345\n' },
            ],
          }),
          category: 'Personal',
          color: 'blue',
          isFavorite: false,
          liveMemberIds: [FB_EDITOR_UID, FB_VIEWER_UID],
          liveRoles: {
            [FB_EDITOR_UID]: 'edit',
            [FB_VIEWER_UID]: 'view',
          },
          sharedWithUserIds: [FB_EDITOR_UID],
          pendingSharedWithUserIds: [FB_PENDING_UID],
          attachments: [
            {
              type: 'image',
              name: 'diagram.png',
              path: `users/${FB_OWNER_UID}/notes/firestore_note_quill_12345/diagram.png`,
              url: `https://firebasestorage.googleapis.com/v0/b/superheromood-54691.appspot.com/o/users%2F${FB_OWNER_UID}%2Fnotes%2Ffirestore_note_quill_12345%2Fdiagram.png?alt=media`,
            },
          ],
          revision: 2,
          createdAt: '2026-02-01T10:00:00.000Z',
          updatedAt: '2026-02-01T11:00:00.000Z',
        },
        {
          id: 'firestore_note_md_67890',
          userId: FB_EDITOR_UID,
          ownerName: 'Bob Editor',
          ownerEmail: 'bob.editor@example.com',
          sourceOwnerId: FB_OWNER_UID,
          sourceNoteId: 'firestore_note_quill_12345',
          title: 'Copied Notes from Alice',
          content: `# Copied Notes\nHere is a picture: ![photo](https://firebasestorage.googleapis.com/v0/b/superheromood-54691.appspot.com/o/users%2F${FB_EDITOR_UID}%2Fnotes%2Ffirestore_note_md_67890%2Fphoto.jpg?alt=media)\nSee original at noted://app/notes/firestore_note_quill_12345`,
          category: 'Personal',
          color: 'mint',
          isFavorite: true,
          attachments: [
            {
              type: 'image',
              name: 'photo.jpg',
              path: `users/${FB_EDITOR_UID}/notes/firestore_note_md_67890/photo.jpg`,
              url: `https://firebasestorage.googleapis.com/v0/b/superheromood-54691.appspot.com/o/users%2F${FB_EDITOR_UID}%2Fnotes%2Ffirestore_note_md_67890%2Fphoto.jpg?alt=media`,
            },
          ],
          revision: 0,
          createdAt: '2026-02-02T10:00:00.000Z',
          updatedAt: '2026-02-02T10:00:00.000Z',
        },
      ],
      userSettings: [
        {
          userId: FB_OWNER_UID,
          preferences: { theme: 'dark', fontSize: 14 },
          timezoneOffsetMinutes: -300,
          notesSchema: 2,
          updatedAt: '2026-02-01T10:00:00.000Z',
        },
      ],
      userFavorites: [
        {
          userId: FB_EDITOR_UID,
          noteId: 'firestore_note_quill_12345',
          createdAt: '2026-02-01T12:00:00.000Z',
        },
      ],
      connectionRequests: [
        {
          id: 'conn_req_101',
          fromUserId: FB_OWNER_UID,
          fromName: 'Alice Owner',
          fromEmail: 'alice.owner@example.com',
          toUserId: FB_CONN_UID,
          toName: 'Eve Connected',
          toEmail: 'eve.conn@example.com',
          status: 'accepted',
          createdAt: '2026-01-10T00:00:00.000Z',
          updatedAt: '2026-01-11T00:00:00.000Z',
        },
      ],
      userInvitations: [
        {
          userId: FB_OWNER_UID,
          emailHash: 'colleague_hash_123',
          email: 'colleague@example.com',
          sentAt: '2026-01-15T00:00:00.000Z',
        },
      ],
      notifications: [
        {
          id: 'notif_001',
          userId: FB_OWNER_UID,
          type: 'live',
          title: 'Bob joined note',
          body: 'Bob joined Sprint Architecture',
          noteId: 'firestore_note_quill_12345',
          actorId: FB_EDITOR_UID,
          actorName: 'Bob Editor',
          read: true,
          emailDispatched: true,
          createdAt: '2026-02-01T11:05:00.000Z',
        },
      ],
      aiChats: [
        {
          userId: FB_OWNER_UID,
          chatId: 'chat_sprint_01',
          title: 'Sprint chat',
          scope: { kind: 'all' },
          createdAt: '2026-02-01T11:10:00.000Z',
          updatedAt: '2026-02-01T11:15:00.000Z',
        },
      ],
      aiMessages: [
        {
          id: 'msg_sprint_01',
          userId: FB_OWNER_UID,
          chatId: 'chat_sprint_01',
          role: 'ai',
          text: 'Here is the summary of Sprint Architecture',
          sources: [
            {
              noteId: 'firestore_note_quill_12345',
              title: 'Quill Delta Sprint Architecture',
            },
          ],
          createdAt: '2026-02-01T11:15:00.000Z',
        },
      ],
    },
    media: [
      {
        sourcePath: `users/${FB_OWNER_UID}/avatar.png`,
        data: dummyAvatar,
        contentType: 'image/png',
      },
      {
        sourcePath: `users/${FB_OWNER_UID}/notes/firestore_note_quill_12345/diagram.png`,
        data: dummyDiagram,
        contentType: 'image/png',
      },
      {
        sourcePath: `users/${FB_EDITOR_UID}/notes/firestore_note_md_67890/photo.jpg`,
        data: dummyPhoto,
        contentType: 'image/jpeg',
      },
    ],
  };
}

// -----------------------------------------------------------------------------
// Test 1: Missing Firebase credentials blocker report on export_firebase.mjs
// -----------------------------------------------------------------------------
test('export_firebase: cleanly halts with blocker report without fabricating bundle when credentials missing', async () => {
  const nonexistentOut = path.join(__dirname, 'tmp_unauth_export_should_not_exist');

  // 1. Run CLI without credentials
  const res = spawnSync(process.execPath, [exportScript, '--out', nonexistentOut], {
    env: { ...process.env, GOOGLE_APPLICATION_CREDENTIALS: '' },
    encoding: 'utf8',
  });

  assert.notEqual(res.status, 0, 'CLI must exit with non-zero exit code');

  const combinedOutput = (res.stdout || '') + (res.stderr || '');
  assert.match(combinedOutput, /BLOCKED/, 'Output must clearly announce BLOCKED state');
  assert.match(
    combinedOutput,
    /Firebase Authentication Viewer/,
    'Must list Firebase Authentication Viewer role',
  );
  assert.match(combinedOutput, /Cloud Datastore Viewer/, 'Must list Cloud Datastore Viewer role');
  assert.match(combinedOutput, /Storage Object Viewer/, 'Must list Storage Object Viewer role');
  assert.match(combinedOutput, /Requirement 10/, 'Must cite Requirement 10 compliance');

  // Verify no fabricated bundle on disk
  await assert.rejects(
    () => fs.access(nonexistentOut),
    'Output directory must NOT be created or fabricated when unauthorized',
  );

  // 2. Programmatic exportFirebaseBundle(null)
  await assert.rejects(
    () => exportFirebaseBundle(null),
    (err) => {
      assert.ok(err.blockerReport, 'Error must include structured blockerReport');
      assert.equal(err.blockerReport.status, 'BLOCKED');
      assert.deepEqual(err.blockerReport.requiredIamRoles, [
        'Firebase Authentication Viewer',
        'Cloud Datastore Viewer',
        'Storage Object Viewer',
      ]);
      return true;
    },
  );
});

// -----------------------------------------------------------------------------
// Test 2: Dry-run import validates all entities with ZERO DB mutations
// -----------------------------------------------------------------------------
test('import_supabase: --dry-run validates full dataset (28-char UIDs, Quill Delta, Markdown, roles) with 0 mutations', async () => {
  const ctx = await createSupabaseTestDb();
  const executor = createPGliteExecutor(ctx);
  const bundle = buildSampleBundle();

  const dryRunResult = await importBundleToExecutor(bundle, executor, { dryRun: true });

  assert.equal(dryRunResult.dryRun, true);
  assert.equal(dryRunResult.errors.length, 0);
  assert.equal(dryRunResult.summary.users, 5);
  assert.equal(dryRunResult.summary.notes, 2);
  assert.equal(dryRunResult.summary.userFavorites, 1);
  assert.equal(dryRunResult.summary.connectionRequests, 1);
  assert.equal(dryRunResult.summary.notifications, 1);
  assert.equal(dryRunResult.summary.aiChats, 1);
  assert.equal(dryRunResult.summary.aiMessages, 1);

  // Verify mapping preview contains valid UUIDs
  assert.ok(dryRunResult.mappingPreview.users.length > 0);
  for (const u of dryRunResult.mappingPreview.users) {
    assert.equal(u.supabaseUuid, firebaseUidToSupabaseUuid(u.legacyFirebaseUid));
  }

  // Verify ZERO rows were written to the database
  const profilesCount = await ctx.db.query('SELECT count(*) AS c FROM public.profiles');
  assert.equal(Number(profilesCount.rows[0].c), 0, 'Profiles table must have 0 rows');

  const notesCount = await ctx.db.query('SELECT count(*) AS c FROM public.notes');
  assert.equal(Number(notesCount.rows[0].c), 0, 'Notes table must have 0 rows');

  const favCount = await ctx.db.query('SELECT count(*) AS c FROM public.user_favorites');
  assert.equal(Number(favCount.rows[0].c), 0, 'Favorites table must have 0 rows');

  const connCount = await ctx.db.query('SELECT count(*) AS c FROM public.connection_requests');
  assert.equal(Number(connCount.rows[0].c), 0, 'Connection requests table must have 0 rows');

  const mapCount = await ctx.db.query('SELECT count(*) AS c FROM public.migration_id_mappings');
  assert.equal(Number(mapCount.rows[0].c), 0, 'Migration mappings table must have 0 rows');

  const authCount = await ctx.db.query('SELECT count(*) AS c FROM auth.users');
  assert.equal(Number(authCount.rows[0].c), 0, 'Auth users table must have 0 rows');

  const storageCount = await ctx.db.query('SELECT count(*) AS c FROM storage.objects');
  assert.equal(Number(storageCount.rows[0].c), 0, 'Storage objects table must have 0 rows');

  await ctx.db.close();
});

// -----------------------------------------------------------------------------
// Test 3: Full live import, validation, idempotency, RLS, and safe rollback
// -----------------------------------------------------------------------------
test('end-to-end migration: live import -> validation passes -> idempotency re-run -> RLS verification -> rollback', async () => {
  const ctx = await createSupabaseTestDb();
  const executor = createPGliteExecutor(ctx);
  const reader = createPGliteReader(ctx);
  const bundle = buildSampleBundle();

  // 1. Live Import
  const liveResult = await importBundleToExecutor(bundle, executor, { dryRun: false });
  assert.equal(liveResult.dryRun, false);
  assert.equal(liveResult.errors.length, 0);

  // 2. Validate Migrated Bundle
  const validation = await validateMigratedBundle(bundle, reader);
  assert.equal(
    validation.ok,
    true,
    `Validation should pass cleanly: ${validation.errors.join('; ')}`,
  );
  assert.equal(validation.errors.length, 0);
  assert.equal(validation.checks.length, 12);
  for (const check of validation.checks) {
    assert.equal(check.passed, true, `Check failed: ${check.name} - ${check.message}`);
  }

  // 3. Inspect specific content & deep-link preservation
  const quillNoteRow = await ctx.db.query(
    'SELECT note_id, user_id, title, content, attachments, live_member_ids, live_roles FROM public.notes WHERE note_id = $1',
    ['firestore_note_quill_12345'],
  );
  assert.equal(quillNoteRow.rows.length, 1);
  const qNote = quillNoteRow.rows[0];
  assert.equal(qNote.note_id, 'firestore_note_quill_12345', 'note_id preserved verbatim');
  assert.equal(qNote.user_id, firebaseUidToSupabaseUuid(FB_OWNER_UID));

  const parsedQuill = JSON.parse(qNote.content);
  assert.equal(parsedQuill.notedDocument, 1, 'notedDocument preserved');
  assert.ok(Array.isArray(parsedQuill.ops), 'ops array preserved');

  // Verify attachment URL rewritten inside Quill Delta ops without breaking formatting
  const ownerUuid = firebaseUidToSupabaseUuid(FB_OWNER_UID);
  const expectedRewrittenDiagramUri = `noted-media://note-media/users/${ownerUuid}/notes/firestore_note_quill_12345/diagram.png`;
  assert.ok(
    qNote.content.includes(expectedRewrittenDiagramUri),
    'Content should contain rewritten private media URI',
  );
  assert.ok(
    !qNote.content.includes('firebasestorage.googleapis.com'),
    'Content should not contain legacy Firebase Storage download URL',
  );
  assert.ok(
    qNote.content.includes('noted://app/notes/firestore_note_quill_12345'),
    'Deep link preserved in content',
  );

  // Inspect Markdown note with copied provenance
  const editorUuid = firebaseUidToSupabaseUuid(FB_EDITOR_UID);
  const mdNoteRow = await ctx.db.query(
    'SELECT note_id, source_owner_id, source_note_id, content FROM public.notes WHERE note_id = $1',
    ['firestore_note_md_67890'],
  );
  assert.equal(mdNoteRow.rows.length, 1);
  const mdNote = mdNoteRow.rows[0];
  assert.equal(mdNote.source_owner_id, ownerUuid);
  assert.equal(mdNote.source_note_id, 'firestore_note_quill_12345');
  assert.ok(mdNote.content.includes('# Copied Notes'));
  assert.ok(
    mdNote.content.includes(
      `noted-media://note-media/users/${editorUuid}/notes/firestore_note_md_67890/photo.jpg`,
    ),
  );

  // 4. Idempotency Check: Re-run import
  const rerunResult = await importBundleToExecutor(bundle, executor, { dryRun: false });
  assert.equal(rerunResult.dryRun, false);

  // Verify everything was skipped because checksums matched
  assert.equal(rerunResult.stats.skipped.user, 5);
  assert.equal(rerunResult.stats.skipped.note, 2);
  assert.equal(rerunResult.stats.skipped.favorite, 1);
  assert.equal(rerunResult.stats.skipped.connection, 1);

  // Table row counts remain identical (0 duplicates)
  const notesAfterRerun = await ctx.db.query('SELECT count(*) AS c FROM public.notes');
  assert.equal(Number(notesAfterRerun.rows[0].c), 2, 'Notes count must remain 2 after re-run');

  const reValidation = await validateMigratedBundle(bundle, reader);
  assert.equal(reValidation.ok, true, 'Validation passes after idempotent re-run');

  // 5. RLS checks as migrated users
  const viewerUuid = firebaseUidToSupabaseUuid(FB_VIEWER_UID);
  const strangerUuid = '77777777-7777-4777-8777-777777777777';

  // Owner can select and update
  const ownerVisible = await ctx.asUser(ownerUuid, (tx) =>
    tx.query('SELECT note_id FROM public.notes WHERE note_id = $1', [
      'firestore_note_quill_12345',
    ]),
  );
  assert.equal(ownerVisible.rows.length, 1);

  // Editor can select and edit note content (revision incremented)
  const editorVisible = await ctx.asUser(editorUuid, (tx) =>
    tx.query('SELECT note_id FROM public.notes WHERE note_id = $1', [
      'firestore_note_quill_12345',
    ]),
  );
  assert.equal(editorVisible.rows.length, 1);

  await ctx.asUser(editorUuid, (tx) =>
    tx.query('UPDATE public.notes SET content = $1, revision = 3 WHERE note_id = $2', [
      '{"notedDocument":1,"ops":[{"insert":"Updated content by editor\\n"}]}',
      'firestore_note_quill_12345',
    ]),
  );

  // Viewer can select, but CANNOT update content (0 rows updated by RLS, commit_note_revision rejects)
  const viewerVisible = await ctx.asUser(viewerUuid, (tx) =>
    tx.query('SELECT note_id FROM public.notes WHERE note_id = $1', [
      'firestore_note_quill_12345',
    ]),
  );
  assert.equal(viewerVisible.rows.length, 1);

  const viewerUpdate = await ctx.asUser(viewerUuid, (tx) =>
    tx.query('UPDATE public.notes SET content = $1, revision = 4 WHERE note_id = $2', [
      'spoofed by viewer',
      'firestore_note_quill_12345',
    ]),
  );
  assert.equal(
    viewerUpdate.affectedRows ?? viewerUpdate.rowCount,
    0,
    'Viewer UPDATE must affect 0 rows under RLS',
  );

  await assert.rejects(
    () =>
      ctx.asUser(viewerUuid, (tx) =>
        tx.query(
          `SELECT public.commit_note_revision('firestore_note_quill_12345', 3, 'Hacked', 'Body', 'Personal', 'blue', false, '[]'::jsonb)`,
        ),
      ),
    /Editing permission denied/,
  );

  // Stranger cannot see the note
  const strangerVisible = await ctx.asUser(strangerUuid, (tx) =>
    tx.query('SELECT note_id FROM public.notes WHERE note_id = $1', [
      'firestore_note_quill_12345',
    ]),
  );
  assert.equal(strangerVisible.rows.length, 0);

  // 6. Native post-migration user & note
  const nativeUserId = '99999999-9999-4999-8999-999999999999';
  await ctx.createAuthUser({
    id: nativeUserId,
    email: 'native@example.com',
    name: 'Native User',
  });
  await ctx.asUser(nativeUserId, (tx) =>
    tx.query(
      `INSERT INTO public.notes (note_id, user_id, title, content)
       VALUES ('native_note_post_mig', $1, 'Native Post-Migration Note', 'Untouched body')`,
      [nativeUserId],
    ),
  );

  // 7. Rollback refuses without a verifiable atomic safety boundary.
  const preview = await rollbackMigratedEntities(executor, { dryRun: true });
  assert.ok(preview.errors.length > 0);
  await assert.rejects(() => rollbackMigratedEntities(executor), /Rollback blocked/);
  const migratedNotesLeft = await ctx.db.query(
    `SELECT note_id FROM public.notes WHERE note_id IN ('firestore_note_quill_12345', 'firestore_note_md_67890')`,
  );
  assert.equal(migratedNotesLeft.rows.length, 2, 'Blocked rollback must preserve migrated notes');
  const mappingsLeft = await ctx.db.query('SELECT count(*) AS c FROM public.migration_id_mappings');
  assert.ok(Number(mappingsLeft.rows[0].c) > 0, 'Blocked rollback must preserve the ledger');

  // CRITICAL: Native post-migration user & note remain 100% untouched!
  const nativeUser = await ctx.db.query(
    'SELECT id, email, name FROM public.profiles WHERE id = $1',
    [nativeUserId],
  );
  assert.equal(nativeUser.rows.length, 1, 'Native post-migration user must remain intact');
  assert.equal(nativeUser.rows[0].email, 'native@example.com');

  const nativeNote = await ctx.asUser(nativeUserId, (tx) =>
    tx.query('SELECT note_id, title FROM public.notes WHERE note_id = $1', [
      'native_note_post_mig',
    ]),
  );
  assert.equal(nativeNote.rows.length, 1, 'Native post-migration note must remain intact');
  assert.equal(nativeNote.rows[0].title, 'Native Post-Migration Note');

  await ctx.db.close();
});

test('createSupabaseAdminExecutor & createSupabaseAdminReader strip non-schema fields, infer MIME types, paginate >1000 rows, and list nested Storage folders', async () => {
  const upsertedByTable = new Map();
  const uploadedBlobs = [];
  let updatedAuthUsers = 0;

  // 1,250 synthetic rows to verify PostgREST 1,000-row pagination
  const bigMappings = Array.from({ length: 1250 }, (_, idx) => ({
    entity_type: 'note',
    firebase_id: `fb_${idx}`,
    supabase_id: `sb_${idx}`,
    checksum: `chk_${idx}`,
    metadata: {},
  }));

  const fakeSupabaseClient = {
    from(table) {
      return {
        select() {
          return {
            async range(from, to) {
              const source = table === 'migration_id_mappings' ? bigMappings : (upsertedByTable.get(table) || []);
              return { data: source.slice(from, to + 1), error: null };
            },
          };
        },
        async upsert(row) {
          const list = upsertedByTable.get(table) || [];
          list.push(row);
          upsertedByTable.set(table, list);
          return { error: null };
        },
      };
    },
    auth: {
      admin: {
        async createUser({ email }) {
          if (email === 'alice.owner@example.com') {
            return { error: { message: 'A user with this email address has already been registered' } };
          }
          return { error: null };
        },
        async getUserById(id) {
          return { data: { user: { id, email_confirmed_at: null } }, error: null };
        },
        async updateUserById() {
          updatedAuthUsers++;
          return { error: null };
        },
        async deleteUser() {
          return { error: null };
        },
      },
    },
    storage: {
      from(bucket) {
        return {
          async upload(targetPath, _buf, opts) {
            uploadedBlobs.push({ bucket, targetPath, contentType: opts.contentType });
            return { error: null };
          },
          async list(prefix = '') {
            if (bucket === 'note-media') {
              if (!prefix) return { data: [{ name: 'users', id: null, metadata: null }], error: null };
              if (prefix === 'users') {
                return {
                  data: [{ name: firebaseUidToSupabaseUuid(FB_OWNER_UID), id: null, metadata: null }],
                  error: null,
                };
              }
              if (prefix === `users/${firebaseUidToSupabaseUuid(FB_OWNER_UID)}`) {
                return { data: [{ name: 'notes', id: null, metadata: null }], error: null };
              }
              if (prefix === `users/${firebaseUidToSupabaseUuid(FB_OWNER_UID)}/notes`) {
                return {
                  data: [{ name: 'firestore_note_quill_12345', id: null, metadata: null }],
                  error: null,
                };
              }
              if (
                prefix ===
                `users/${firebaseUidToSupabaseUuid(FB_OWNER_UID)}/notes/firestore_note_quill_12345`
              ) {
                return {
                  data: [{ name: 'diagram.png', id: 'obj-1', metadata: { mimetype: 'image/png' } }],
                  error: null,
                };
              }
            }
            return { data: [], error: null };
          },
        };
      },
    },
  };

  const adminExecutor = createSupabaseAdminExecutor(fakeSupabaseClient);
  const existing = await adminExecutor.getExistingMappings();
  assert.equal(existing.size, 1250);

  // Add orphaned records to verify orphan FK sanitization
  const bundle = buildSampleBundle();
  bundle.firestore.userFavorites.push({
    userId: 'deleted_ghost_user_999',
    noteId: 'missing_note_999',
    createdAt: '2026-02-01T00:00:00.000Z',
  });
  bundle.firestore.notes[1].sourceOwnerId = 'deleted_ghost_author_888';

  const importRes = await importBundleToExecutor(bundle, adminExecutor, { dryRun: false });
  assert.equal(updatedAuthUsers, 1);
  assert.equal(importRes.stats.orphanedSkipped.userFavorites, 1);

  // Verify NO table received `checksum` or `userId` extraneous fields
  for (const [table, rows] of upsertedByTable.entries()) {
    for (const row of rows) {
      if (table !== 'migration_id_mappings') {
        assert.equal('checksum' in row, false, `${table} row leaked checksum column`);
      }
      assert.equal('userId' in row, false, `${table} row leaked camelCase userId column`);
    }
  }

  // Verify orphan sourceOwnerId was sanitized to null
  const importedCopyNote = (upsertedByTable.get('notes') || []).find(
    (n) => n.note_id === 'firestore_note_md_67890',
  );
  assert.equal(importedCopyNote.source_owner_id, null);

  // Verify NO uploaded blob used `application/octet-stream`
  assert.equal(uploadedBlobs.length, 3);
  for (const blob of uploadedBlobs) {
    assert.notEqual(blob.contentType, 'application/octet-stream');
  }

  // Verify recursive Storage listing finds nested note-media objects
  const adminReader = createSupabaseAdminReader(fakeSupabaseClient);
  const listedStorage = await adminReader.getStorageObjects();
  assert.ok(
    listedStorage.some(
      (o) =>
        o.bucket_id === 'note-media' &&
        o.name ===
          `users/${firebaseUidToSupabaseUuid(FB_OWNER_UID)}/notes/firestore_note_quill_12345/diagram.png`,
    ),
  );
});
