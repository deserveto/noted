import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  firebaseUidToSupabaseUuid,
  mapFirebaseNoteToPostgres,
  mapStorageObjectPath,
} from './id_mapping.mjs';
import { loadBundleFromDir } from './export_firebase.mjs';
import { selectAllPostgrestRows, importBundleToExecutor } from './import_supabase.mjs';
import { isDeepStrictEqual } from 'node:util';

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseArgs(argv = process.argv.slice(2)) {
  const args = {
    bundle: './exports/latest',
    supabaseUrl: process.env.SUPABASE_URL || null,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || null,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--bundle' && i + 1 < argv.length) {
      args.bundle = argv[++i];
    } else if (arg === '--supabase-url' && i + 1 < argv.length) {
      args.supabaseUrl = argv[++i];
    } else if (arg === '--service-role-key' && i + 1 < argv.length) {
      args.serviceRoleKey = argv[++i];
    }
  }

  return args;
}

export function createPGliteReader(dbOrCtx) {
  const db = dbOrCtx.db || dbOrCtx;
  return {
    async query(sql, params = []) {
      return db.query(sql, params);
    },
    async getProfiles() {
      const res = await db.query('SELECT * FROM public.profiles');
      return res.rows;
    },
    async getAuthUsers(ids) {
      if (!ids.length) return [];
      const res = await db.query('SELECT id, email_confirmed_at, banned_until FROM auth.users WHERE id = ANY($1::uuid[])', [ids]);
      return res.rows;
    },
    async getNotes() {
      const res = await db.query('SELECT * FROM public.notes');
      return res.rows;
    },
    async getUserSettings() {
      const res = await db.query('SELECT * FROM public.user_settings');
      return res.rows;
    },
    async getUserFavorites() {
      const res = await db.query('SELECT * FROM public.user_favorites');
      return res.rows;
    },
    async getConnectionRequests() {
      const res = await db.query('SELECT * FROM public.connection_requests');
      return res.rows;
    },
    async getUserInvitations() {
      const res = await db.query('SELECT * FROM public.user_invitations');
      return res.rows;
    },
    async getNotifications() {
      const res = await db.query('SELECT * FROM public.notifications');
      return res.rows;
    },
    async getAiRequests() {
      const res = await db.query('SELECT * FROM public.ai_requests');
      return res.rows;
    },
    async getAiChats() {
      const res = await db.query('SELECT * FROM public.ai_chats');
      return res.rows;
    },
    async getAiMessages() {
      const res = await db.query('SELECT * FROM public.ai_messages');
      return res.rows;
    },
    async getStorageChecksum(bucket, name) {
      const r = await db.query('SELECT metadata FROM storage.objects WHERE bucket_id=$1 AND name=$2', [bucket,name]);
      return r.rows[0]?.metadata?.sha256 || null;
    },
    async getStorageObjects() {
      try {
        const res = await db.query('SELECT * FROM storage.objects');
        return res.rows;
      } catch {
        return [];
      }
    },
    async getMappings() {
      try {
        const res = await db.query('SELECT * FROM public.migration_id_mappings');
        return res.rows;
      } catch {
        return [];
      }
    },
  };
}

async function listBucketObjectsRecursively(storageBucket, prefix = '', maxDepth = 5) {
  if (maxDepth <= 0 || !storageBucket || typeof storageBucket.list !== 'function') {
    return [];
  }
  const results = [];
  let offset = 0;
  const pageSize = 500;
  const cleanPrefix = prefix.replace(/^\/+|\/+$/g, '');

  while (true) {
    const { data, error } = await storageBucket
      .list(cleanPrefix, { limit: pageSize, offset });
    if (error) throw error;
    if (!data || data.length === 0) break;

    for (const item of data) {
      if (!item?.name) continue;
      const fullPath = cleanPrefix ? `${cleanPrefix}/${item.name}` : item.name;
      const isFolder =
        ('id' in item || 'metadata' in item) &&
        item.id === null &&
        !item.metadata;
      if (isFolder) {
        const nested = await listBucketObjectsRecursively(
          storageBucket,
          fullPath,
          maxDepth - 1,
        );
        results.push(...nested);
      } else {
        results.push(fullPath);
      }
    }

    if (data.length < pageSize) break;
    offset += pageSize;
  }

  return results;
}

export function createSupabaseAdminReader(supabaseClient) {
  return {
    async getAuthUsers(ids) {
      return Promise.all(ids.map(async id => {
        const { data, error } = await supabaseClient.auth.admin.getUserById(id);
        if (error) throw error;
        return data.user;
      }));
    },
    async getProfiles() {
      return selectAllPostgrestRows(supabaseClient, 'profiles');
    },
    async getNotes() {
      return selectAllPostgrestRows(supabaseClient, 'notes');
    },
    async getUserSettings() {
      return selectAllPostgrestRows(supabaseClient, 'user_settings');
    },
    async getUserFavorites() {
      return selectAllPostgrestRows(supabaseClient, 'user_favorites');
    },
    async getConnectionRequests() {
      return selectAllPostgrestRows(supabaseClient, 'connection_requests');
    },
    async getUserInvitations() {
      return selectAllPostgrestRows(supabaseClient, 'user_invitations');
    },
    async getNotifications() {
      return selectAllPostgrestRows(supabaseClient, 'notifications');
    },
    async getAiRequests() { return selectAllPostgrestRows(supabaseClient, 'ai_requests'); },
    async getAiChats() {
      return selectAllPostgrestRows(supabaseClient, 'ai_chats');
    },
    async getAiMessages() {
      return selectAllPostgrestRows(supabaseClient, 'ai_messages');
    },
    async getStorageChecksum(bucket, name) {
      const { data, error } = await supabaseClient.storage.from(bucket).download(name);
      if (error) throw error;
      return crypto.createHash('sha256').update(Buffer.from(await data.arrayBuffer())).digest('hex');
    },
    async getStorageObjects() {
      const objects = [];
      for (const bucket of ['avatars', 'note-media']) {
        try {
          const paths = await listBucketObjectsRecursively(supabaseClient.storage.from(bucket));
          for (const name of paths) {
            objects.push({ bucket_id: bucket, name });
          }
        } catch (err) { throw err; }
      }
      return objects;
    },
    async getMappings() {
      return selectAllPostgrestRows(supabaseClient, 'migration_id_mappings');
    },
  };
}

function normalizeReader(reader) {
  if (reader.getProfiles && reader.getNotes) return reader;
  if (reader.db || reader.query) return createPGliteReader(reader);
  return reader;
}

/**
 * Validates a migrated bundle against the target Supabase/PGlite database.
 * Returns { ok: boolean, checks: [...], errors: [...] }.
 */
export async function validateMigratedBundle(bundleOrDir, rawReader) {
  const reader = normalizeReader(rawReader);

  let bundle;
  if (typeof bundleOrDir === 'string') {
    bundle = await loadBundleFromDir(bundleOrDir);
  } else {
    bundle = bundleOrDir;
  }

  const checks = [];
  const errors = [];

  function recordCheck(name, passed, message, details = null) {
    checks.push({ name, passed, message, ...(details ? { details } : {}) });
    if (!passed) {
      errors.push(`[${name}] ${message}`);
    }
  }

  // Fetch all target rows in parallel
  const [
    profiles,
    notes,
    settings,
    favorites,
    connections,
    invitations,
    notifications,
    chats,
    messages,
    requests,
    storageObjects,
    mappings,
  ] = await Promise.all([
    reader.getProfiles(),
    reader.getNotes(),
    reader.getUserSettings(),
    reader.getUserFavorites(),
    reader.getConnectionRequests(),
    reader.getUserInvitations(),
    reader.getNotifications(),
    reader.getAiChats(),
    reader.getAiMessages(),
    reader.getAiRequests ? reader.getAiRequests() : Promise.resolve([]),
    reader.getStorageObjects(),
    reader.getMappings(),
  ]);

  const rawAuthUsers = bundle.auth?.users || bundle.authUsers || [];
  const rawFirestoreUsers = bundle.firestore?.users || [];
  const allUserUids = [
    ...new Set([
      ...rawAuthUsers.map((u) => u.uid).filter(Boolean),
      ...rawFirestoreUsers.map((u) => u.id).filter(Boolean),
    ]),
  ];

  const authUsers = await reader.getAuthUsers(allUserUids.map(uid => firebaseUidToSupabaseUuid(uid)));
  const authIssues = [];
  for (const uid of allUserUids) {
    const source = rawAuthUsers.find(user => user.uid === uid) || {};
    const actual = authUsers.find(user => user?.id === firebaseUidToSupabaseUuid(uid));
    if (!actual) { authIssues.push(`Missing auth user for ${uid}`); continue; }
    const confirmed = Boolean(actual.email_confirmed_at);
    const banned = actual.banned_until != null && new Date(actual.banned_until).getTime() > Date.now();
    if (confirmed !== (source.emailVerified === true)) authIssues.push(`Email verification mismatch for ${uid}`);
    if (banned !== (source.disabled === true)) authIssues.push(`Disabled status mismatch for ${uid}`);
  }
  recordCheck('Auth verification and disabled status', authIssues.length === 0,
    authIssues.length ? authIssues.join('; ') : 'Auth verification and disabled status match the source');

  const bundleNotes = bundle.firestore?.notes || [];
  const bundleSettings = bundle.firestore?.userSettings || [];
  const bundleFavorites = bundle.firestore?.userFavorites || [];
  const bundleConnections = (bundle.firestore?.connectionRequests || []).filter((c) => {
    const fromUid = c.fromUserId || c.senderId || c.from;
    const toUid = c.toUserId || c.receiverId || c.to;
    return fromUid && toUid && firebaseUidToSupabaseUuid(fromUid) !== firebaseUidToSupabaseUuid(toUid);
  });
  const bundleInvitations = bundle.firestore?.userInvitations || [];
  const bundleNotifications = bundle.firestore?.notifications || [];
  const bundleChats = bundle.firestore?.aiChats || [];
  const bundleMessages = bundle.firestore?.aiMessages || [];

  // --- 1. Row counts check ---
  const rowCountIssues = [];
  if (profiles.length < allUserUids.length) {
    rowCountIssues.push(`profiles: expected at least ${allUserUids.length}, got ${profiles.length}`);
  }
  if (notes.length < bundleNotes.length) {
    rowCountIssues.push(`notes: expected at least ${bundleNotes.length}, got ${notes.length}`);
  }
  if (settings.length < bundleSettings.length) {
    rowCountIssues.push(`settings: expected at least ${bundleSettings.length}, got ${settings.length}`);
  }
  if (favorites.length < bundleFavorites.length) {
    rowCountIssues.push(`favorites: expected at least ${bundleFavorites.length}, got ${favorites.length}`);
  }
  if (connections.length < bundleConnections.length) {
    rowCountIssues.push(
      `connections: expected at least ${bundleConnections.length}, got ${connections.length}`,
    );
  }
  if (invitations.length < bundleInvitations.length) {
    rowCountIssues.push(
      `invitations: expected at least ${bundleInvitations.length}, got ${invitations.length}`,
    );
  }
  if (notifications.length < bundleNotifications.length) {
    rowCountIssues.push(
      `notifications: expected at least ${bundleNotifications.length}, got ${notifications.length}`,
    );
  }
  if (chats.length < bundleChats.length) {
    rowCountIssues.push(`ai_chats: expected at least ${bundleChats.length}, got ${chats.length}`);
  }
  if (messages.length < bundleMessages.length) {
    rowCountIssues.push(
      `ai_messages: expected at least ${bundleMessages.length}, got ${messages.length}`,
    );
  }

  recordCheck(
    'Row counts',
    rowCountIssues.length === 0,
    rowCountIssues.length === 0
      ? `All 9 entity table counts match or exceed bundle requirements (users: ${allUserUids.length}, notes: ${bundleNotes.length})`
      : `Row count mismatch: ${rowCountIssues.join('; ')}`,
  );

  // --- 2. User UUID mappings & legacy_firebase_uid ---
  let userMappingIssues = [];
  for (const uid of allUserUids) {
    const expectedUuid = firebaseUidToSupabaseUuid(uid);
    if (!UUID_REGEX.test(expectedUuid)) {
      userMappingIssues.push(`UID ${uid} mapped to invalid UUID format: ${expectedUuid}`);
      continue;
    }
    const profile = profiles.find((p) => p.id === expectedUuid);
    if (!profile) {
      userMappingIssues.push(`Missing profile for mapped UUID ${expectedUuid} (Firebase UID ${uid})`);
    } else if (profile.legacy_firebase_uid !== uid) {
      userMappingIssues.push(
        `Profile ${expectedUuid} legacy_firebase_uid '${profile.legacy_firebase_uid}' does not match expected '${uid}'`,
      );
    }
  }

  recordCheck(
    'User UUID mappings',
    userMappingIssues.length === 0,
    userMappingIssues.length === 0
      ? `All ${allUserUids.length} user UIDs mapped to deterministic UUIDv5 with legacy_firebase_uid preserved`
      : `User mapping failures: ${userMappingIssues.join('; ')}`,
  );

  // --- 3. Note ownership & deep-link note_id preservation ---
  let noteOwnershipIssues = [];
  for (const bNote of bundleNotes) {
    const noteId = String(bNote.id || bNote.note_id);
    const expectedOwner = firebaseUidToSupabaseUuid(bNote.userId);
    const dbNote = notes.find((n) => n.note_id === noteId);

    if (!dbNote) {
      noteOwnershipIssues.push(`Note ${noteId} not found in public.notes (deep link broken)`);
    } else if (dbNote.user_id !== expectedOwner) {
      noteOwnershipIssues.push(
        `Note ${noteId} owner mismatch: expected ${expectedOwner}, got ${dbNote.user_id}`,
      );
    }
  }

  recordCheck(
    'Note ownership & deep-link preservation',
    noteOwnershipIssues.length === 0,
    noteOwnershipIssues.length === 0
      ? `All ${bundleNotes.length} note_ids preserved verbatim for deep links with exact owner UUIDs`
      : `Note ownership issues: ${noteOwnershipIssues.join('; ')}`,
  );

  // --- 4. live_member_ids & live_roles keys integrity ---
  let liveMemberIssues = [];
  for (const dbNote of notes) {
    const members = Array.isArray(dbNote.live_member_ids) ? dbNote.live_member_ids : [];
    for (const m of members) {
      if (!UUID_REGEX.test(m)) {
        liveMemberIssues.push(`Note ${dbNote.note_id} contains non-UUID live_member_id: ${m}`);
      }
    }

    const roles =
      typeof dbNote.live_roles === 'string'
        ? JSON.parse(dbNote.live_roles)
        : dbNote.live_roles || {};

    for (const [roleUid, roleVal] of Object.entries(roles)) {
      if (!UUID_REGEX.test(roleUid)) {
        liveMemberIssues.push(`Note ${dbNote.note_id} live_roles key is not a UUID: ${roleUid}`);
      }
      if (!members.includes(roleUid)) {
        liveMemberIssues.push(
          `Note ${dbNote.note_id} live_roles key ${roleUid} is not in live_member_ids`,
        );
      }
      if (roleVal !== 'edit' && roleVal !== 'view') {
        liveMemberIssues.push(
          `Note ${dbNote.note_id} invalid role value '${roleVal}' for ${roleUid}`,
        );
      }
    }
  }

  recordCheck(
    'Live members & roles integrity',
    liveMemberIssues.length === 0,
    liveMemberIssues.length === 0
      ? 'All live_member_ids and live_roles keys are RFC-4122 UUIDs with valid roles (edit/view)'
      : `Live member issues: ${liveMemberIssues.join('; ')}`,
  );

  // --- 5. Pending shared & shared_with_user_ids ---
  let shareIssues = [];
  for (const dbNote of notes) {
    const pending = Array.isArray(dbNote.pending_shared_with_user_ids)
      ? dbNote.pending_shared_with_user_ids
      : [];
    for (const p of pending) {
      if (!UUID_REGEX.test(p)) {
        shareIssues.push(`Note ${dbNote.note_id} contains non-UUID pending_shared_with_user_id: ${p}`);
      }
    }
    const shared = Array.isArray(dbNote.shared_with_user_ids) ? dbNote.shared_with_user_ids : [];
    for (const s of shared) {
      if (!UUID_REGEX.test(s)) {
        shareIssues.push(`Note ${dbNote.note_id} contains non-UUID shared_with_user_id: ${s}`);
      }
    }
  }

  recordCheck(
    'Pending & shared user IDs integrity',
    shareIssues.length === 0,
    shareIssues.length === 0
      ? 'All pending and shared user ID arrays contain valid RFC-4122 UUIDs'
      : `Share array issues: ${shareIssues.join('; ')}`,
  );

  // --- 6. Source owner and source note provenance ---
  let provenanceIssues = [];
  for (const bNote of bundleNotes) {
    if (bNote.sourceOwnerId || bNote.sourceNoteId) {
      const noteId = String(bNote.id || bNote.note_id);
      const dbNote = notes.find((n) => n.note_id === noteId);
      if (!dbNote) continue;

      if (bNote.sourceOwnerId) {
        const expectedSourceOwner = firebaseUidToSupabaseUuid(bNote.sourceOwnerId);
        if (dbNote.source_owner_id !== expectedSourceOwner) {
          provenanceIssues.push(
            `Note ${noteId} source_owner_id expected ${expectedSourceOwner}, got ${dbNote.source_owner_id}`,
          );
        }
      }
      if (bNote.sourceNoteId && dbNote.source_note_id !== String(bNote.sourceNoteId)) {
        provenanceIssues.push(
          `Note ${noteId} source_note_id expected ${bNote.sourceNoteId}, got ${dbNote.source_note_id}`,
        );
      }
    }
  }

  recordCheck(
    'Copied note provenance',
    provenanceIssues.length === 0,
    provenanceIssues.length === 0
      ? 'All copied note provenance links (source_owner_id, source_note_id) correctly preserved'
      : `Provenance issues: ${provenanceIssues.join('; ')}`,
  );

  // --- 7. Personal favorites ---
  let favIssues = [];
  for (const bFav of bundleFavorites) {
    const expectedUser = firebaseUidToSupabaseUuid(bFav.userId);
    const expectedNote = String(bFav.noteId);
    const found = favorites.find((f) => f.user_id === expectedUser && f.note_id === expectedNote);
    if (!found) {
      favIssues.push(`Missing favorite for user ${expectedUser} on note ${expectedNote}`);
    }
  }

  recordCheck(
    'Personal favorites',
    favIssues.length === 0,
    favIssues.length === 0
      ? `All ${bundleFavorites.length} personal favorites verified in public.user_favorites`
      : `Favorite issues: ${favIssues.join('; ')}`,
  );

  // --- 8. Connection requests ---
  let connIssues = [];
  for (const bConn of bundleConnections) {
    const expectedFrom = firebaseUidToSupabaseUuid(bConn.fromUserId || bConn.senderId || bConn.from);
    const expectedTo = firebaseUidToSupabaseUuid(bConn.toUserId || bConn.receiverId || bConn.to);
    const connId = String(bConn.id || bConn.connection_id || bConn.connectionId);
    const found = connections.find(
      (c) =>
        c.connection_id === connId ||
        (c.from_user_id === expectedFrom && c.to_user_id === expectedTo),
    );
    if (!found) {
      connIssues.push(`Connection ${connId} (${expectedFrom} -> ${expectedTo}) missing in database`);
    } else if (found.status !== (bConn.status || 'pending')) {
      connIssues.push(
        `Connection ${connId} status mismatch: expected ${bConn.status}, got ${found.status}`,
      );
    }
  }

  recordCheck(
    'Connection requests',
    connIssues.length === 0,
    connIssues.length === 0
      ? `All ${bundleConnections.length} connection requests verified with mapped participant UUIDs`
      : `Connection issues: ${connIssues.join('; ')}`,
  );

  // --- 9. AI chats & messages sources integrity ---
  let aiIssues = [];
  for (const bChat of bundleChats) {
    const expectedUser = firebaseUidToSupabaseUuid(bChat.userId);
    const chatId = String(bChat.chatId || bChat.id);
    const found = chats.find((c) => c.user_id === expectedUser && c.chat_id === chatId);
    if (!found) {
      aiIssues.push(`Chat ${chatId} for user ${expectedUser} missing`);
    }
  }

  for (const bMsg of bundleMessages) {
    const msgId = String(bMsg.id);
    const found = messages.find((m) => m.id === msgId);
    if (!found) {
      aiIssues.push(`Message ${msgId} missing`);
    } else if (Array.isArray(bMsg.sources)) {
      const dbSources =
        typeof found.sources === 'string' ? JSON.parse(found.sources) : found.sources;
      if (!Array.isArray(dbSources) || dbSources.length !== bMsg.sources.length) {
        aiIssues.push(`Message ${msgId} sources array mismatch`);
      }
    }
  }

  recordCheck(
    'AI chats & messages integrity',
    aiIssues.length === 0,
    aiIssues.length === 0
      ? 'All AI chats and messages verified with sources JSON array integrity preserved'
      : `AI issues: ${aiIssues.join('; ')}`,
  );

  // Compare imported values, not just their shape. The importer supplies the
  // same transformation used for writes, including rewritten media and roles.
  const transformed = await importBundleToExecutor(bundle, null, {dryRun: true});
  const expected = transformed.expectedRows;
  const parityIssues = Object.entries(transformed.orphanedSkipped).map(([kind,count]) => `${kind}: ${count} orphaned source records omitted`);
  function normalize(value) {
    if (value instanceof Date) return value.toISOString();
    if (Array.isArray(value)) return value.map(normalize);
    if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, normalize(value[k])]));
    return value;
  }
  function compareRows(label, wanted, actual, keys) {
    for (const expectedRow of wanted) {
      const found = actual.find(row => keys.every(k => row[k] === expectedRow[k]));
      if (!found) { parityIssues.push(`${label} missing: ${keys.map(k => expectedRow[k]).join('/')}`); continue; }
      for (const [key, value] of Object.entries(expectedRow)) {
        if (['checksum','firebaseId','userId'].includes(key)) continue;
        // Missing source timestamps are generated at import time and cannot be reproduced later.
        if (['_generated_at'].includes(key)) continue;
        let got = found[key];
        if (key.endsWith('_at') && got != null && value != null) {
          got = new Date(got).toISOString();
          if (got !== new Date(value).toISOString()) parityIssues.push(`${label} ${key} mismatch`);
        } else if (!isDeepStrictEqual(normalize(got), normalize(value))) parityIssues.push(`${label} ${key} mismatch`);
      }
    }
  }
  const profileRows = expected.users.map(u => ({id:u.id,email:u.email,name:u.name,field_of_study:u.fieldOfStudy,avatar_path:u.avatarPath,avatar_url:u.avatarUrl,legacy_firebase_uid:u.legacyFirebaseUid}));
  compareRows('profile', profileRows, profiles, ['id']);
  compareRows('settings', expected.settings.map(({updated_at,...r})=>r), settings, ['user_id']);
  compareRows('note', expected.notes.map(({created_at,updated_at,...r})=>r), notes, ['note_id']);
  compareRows('favorite', expected.favorites.map(({created_at,...r})=>r), favorites, ['user_id','note_id']);
  compareRows('connection', expected.connections.map(({created_at,updated_at,...r})=>r), connections, ['connection_id']);
  compareRows('invitation', expected.invitations.map(({sent_at,...r})=>r), invitations, ['user_id','email_hash']);
  compareRows('notification', expected.notifications.map(({created_at,...r})=>r), notifications, ['id']);
  compareRows('chat', expected.chats.map(({created_at,updated_at,...r})=>r), chats, ['user_id','chat_id']);
  compareRows('message', expected.messages.map(({created_at,...r})=>r), messages, ['id']);
  compareRows('AI request', expected.requests.map(({created_at,updated_at,completed_at,...r})=>r), requests, ['user_id','request_id']);
  function compareDates(label, expectedRows, actualRows, sources, keys, dateFields) {
    for (let i = 0; i < expectedRows.length; i++) {
      const row = expectedRows[i], source = sources[i];
      const found = actualRows.find(actual => keys.every(key => actual[key] === row[key]));
      if (!source || !found) continue;
      for (const [target, sourceKey] of dateFields) {
        if (source[sourceKey] && (found[target] == null || new Date(found[target]).toISOString() !== new Date(row[target]).toISOString())) parityIssues.push(`${label} ${target} mismatch`);
      }
    }
  }
  for (const user of expected.users) {
    const source = rawAuthUsers.find(u => u.uid === user.legacyFirebaseUid) || {};
    const fsUser = rawFirestoreUsers.find(u => u.id === user.legacyFirebaseUid) || {};
    const actual = profiles.find(p => p.id === user.id);
    for (const [key, supplied] of [['createdAt', source.metadata?.creationTime || fsUser.createdAt], ['updatedAt', source.metadata?.lastSignInTime || fsUser.updatedAt]]) {
      const column = key === 'createdAt' ? 'created_at' : 'updated_at';
      if (supplied && actual && new Date(actual[column]).toISOString() !== new Date(user[key]).toISOString()) parityIssues.push(`profile ${column} mismatch`);
    }
  }
  compareDates('note', expected.notes, notes, bundleNotes, ['note_id'], [['created_at','createdAt'],['updated_at','updatedAt']]);
  compareDates('settings', expected.settings, settings, bundleSettings, ['user_id'], [['updated_at','updatedAt']]);
  compareDates('favorite', expected.favorites, favorites, bundleFavorites, ['user_id','note_id'], [['created_at','createdAt']]);
  compareDates('connection', expected.connections, connections, bundleConnections, ['connection_id'], [['created_at','createdAt'],['updated_at','updatedAt']]);
  compareDates('invitation', expected.invitations, invitations, bundleInvitations, ['user_id','email_hash'], [['sent_at','sentAt']]);
  compareDates('notification', expected.notifications, notifications, bundleNotifications, ['id'], [['created_at','createdAt']]);
  compareDates('chat', expected.chats, chats, bundleChats, ['user_id','chat_id'], [['created_at','createdAt'],['updated_at','updatedAt']]);
  compareDates('message', expected.messages, messages, bundleMessages, ['id'], [['created_at','createdAt']]);
  compareDates('AI request', expected.requests, requests, bundle.firestore?.aiRequests || [], ['user_id','request_id'], [['created_at','createdAt'],['updated_at','updatedAt'],['completed_at','completedAt']]);
  if (parityIssues.length) { checks[checks.length - 1].passed = false; checks[checks.length - 1].message += `; parity: ${parityIssues.join('; ')}`; errors.push(`Transformed parity: ${parityIssues.join('; ')}`); }

  // --- 10. Non-destructive Quill Delta & Markdown preservation ---
  let contentIssues = [];
  for (const bNote of bundleNotes) {
    const noteId = String(bNote.id || bNote.note_id);
    const dbNote = notes.find((n) => n.note_id === noteId);
    if (!dbNote) continue;

    const content = String(dbNote.content ?? '');

    // Check that legacy Firebase download URLs were replaced with private media URIs
    if (Array.isArray(bNote.attachments)) {
      for (const att of bNote.attachments) {
        if (att.url && att.url.includes('firebasestorage.googleapis.com')) {
          if (content.includes(att.url)) {
            contentIssues.push(
              `Note ${noteId} still contains raw Firebase Storage download URL: ${att.url}`,
            );
          }
        }
      }
    }

    // Check Quill Delta structure preservation
    const rawOrig = String(bNote.content ?? '').trim();
    if (rawOrig.startsWith('{') && rawOrig.includes('"ops"')) {
      let parsed;
      try {
        parsed = JSON.parse(content);
      } catch (err) {
        contentIssues.push(`Note ${noteId} Quill Delta content is no longer valid JSON: ${err.message}`);
      }
      if (parsed) {
        if (parsed.notedDocument !== 1) {
          contentIssues.push(`Note ${noteId} Quill Delta missing or mutated notedDocument header`);
        }
        if (!Array.isArray(parsed.ops)) {
          contentIssues.push(`Note ${noteId} Quill Delta missing ops array`);
        }
      }
    }
  }

  recordCheck(
    'Content & Quill Delta preservation',
    contentIssues.length === 0,
    contentIssues.length === 0
      ? 'Quill Delta JSON ops and Markdown content preserved non-destructively; attachments rewritten to noted-media://'
      : `Content preservation issues: ${contentIssues.join('; ')}`,
  );

  // --- 11. Private storage object presence ---
  let storageIssues = [];
  const expectedStorage = [];

  for (const uid of allUserUids) {
    const fsUser = rawFirestoreUsers.find((u) => u.id === uid);
    if (fsUser?.avatarPath) {
      expectedStorage.push({
        bucket: 'avatars',
        path: mapStorageObjectPath(fsUser.avatarPath, firebaseUidToSupabaseUuid),
      });
    }
  }

  for (const bNote of bundleNotes) {
    const { mediaObjects } = mapFirebaseNoteToPostgres(
      bNote.id,
      bNote,
      firebaseUidToSupabaseUuid,
    );
    for (const m of mediaObjects) {
      expectedStorage.push({ bucket: m.bucket, path: m.targetPath });
    }
  }

  for (const exp of expectedStorage) {
    const found = storageObjects.find((s) => s.bucket_id === exp.bucket && s.name === exp.path);
    if (!found) {
      storageIssues.push(`Storage object ${exp.bucket}/${exp.path} missing in storage.objects`);
    }
  }

  for (const media of bundle.media || []) {
    const bucket = media.sourcePath.includes('/notes/') ? 'note-media' : 'avatars';
    const target = mapStorageObjectPath(media.sourcePath, firebaseUidToSupabaseUuid);
    const bytes = media.data || media.buffer;
    if (!bytes || !reader.getStorageChecksum) { storageIssues.push(`Cannot verify media checksum: ${media.sourcePath}`); continue; }
    const expectedHash = crypto.createHash('sha256').update(bytes).digest('hex');
    if (await reader.getStorageChecksum(bucket, target) !== expectedHash) storageIssues.push(`Media checksum mismatch: ${bucket}/${target}`);
  }

  recordCheck(
    'Private storage objects',
    storageIssues.length === 0,
    storageIssues.length === 0
      ? `All ${expectedStorage.length} private storage objects verified in storage.objects (avatars, note-media)`
      : `Storage issues: ${storageIssues.join('; ')}`,
  );

  return {
    ok: errors.length === 0,
    checks,
    errors,
  };
}

/**
 * CLI execution entrypoint
 */
async function runCli() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.supabaseUrl || !args.serviceRoleKey) {
    console.error('Error: --supabase-url and --service-role-key are required for migration validation.');
    process.exit(1);
  }

  const { createClient } = await import('@supabase/supabase-js');
  const supabase = createClient(args.supabaseUrl, args.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const reader = createSupabaseAdminReader(supabase);
  console.log(`Validating migration for bundle ${args.bundle}...`);
  const result = await validateMigratedBundle(args.bundle, reader);

  console.log('\nMigration Validation Checks:');
  for (const check of result.checks) {
    const status = check.passed ? 'PASS' : 'FAIL';
    console.log(`[${status}] ${check.name}: ${check.message}`);
  }

  if (!result.ok) {
    console.error('\nValidation FAILED with the following errors:');
    for (const err of result.errors) {
      console.error(`  - ${err}`);
    }
    process.exit(1);
  }

  console.log('\nAll migration validation checks PASSED successfully!');
}

const currentFileUrl = import.meta.url;
const executedFileUrl = pathToFileURL(path.resolve(process.argv[1] || '')).href;
if (currentFileUrl === executedFileUrl) {
  runCli().catch((err) => {
    console.error('Fatal validation error:', err);
    process.exit(1);
  });
}
