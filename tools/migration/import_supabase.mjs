import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  firebaseUidToSupabaseUuid,
  inferAllowedMimeType,
  mapFirebaseNoteToPostgres,
  mapStorageObjectPath,
  canonicalPrivateMediaUri,
  normalizeTimestamp,
  computeEntityChecksum,
} from './id_mapping.mjs';
import { loadBundleFromDir } from './export_firebase.mjs';

export function parseArgs(argv = process.argv.slice(2)) {
  const args = {
    bundle: './exports/latest',
    dryRun: false,
    sealRollback: false,
    supabaseUrl: process.env.SUPABASE_URL || null,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || null,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--bundle' && i + 1 < argv.length) {
      args.bundle = argv[++i];
    } else if (arg === '--dry-run') {
      args.dryRun = true;
    } else if (arg === '--seal-rollback') {
      args.sealRollback = true;
    } else if (arg === '--supabase-url' && i + 1 < argv.length) {
      args.supabaseUrl = argv[++i];
    } else if (arg === '--service-role-key' && i + 1 < argv.length) {
      args.serviceRoleKey = argv[++i];
    }
  }

  return args;
}

function toPgUuidArray(arr) {
  if (!Array.isArray(arr) || arr.length === 0) return '{}';
  return '{' + arr.filter(Boolean).join(',') + '}';
}

/**
 * Paginates PostgREST `.select()` calls in 1,000-row pages so large production
 * tables are never truncated at PostgREST's default 1,000-row cap.
 */
export async function selectAllPostgrestRows(supabaseClient, table, columns = '*') {
  const rows = [];
  const pageSize = 1000;
  let offset = 0;

  while (true) {
    const query = supabaseClient.from(table).select(columns);
    if (typeof query.range !== 'function') {
      const { data, error } = await query;
      if (error) throw error;
      return data || [];
    }
    const { data, error } = await query.range(offset, offset + pageSize - 1);
    if (error) throw error;
    const batch = data || [];
    rows.push(...batch);
    if (batch.length < pageSize) break;
    offset += pageSize;
  }

  return rows;
}

/**
 * Creates a PGlite-backed executor adapter for local and in-memory test imports.
 */
export function createPGliteExecutor(dbOrCtx) {
  const db = dbOrCtx.db || dbOrCtx;

  async function ensureSetup() {
    await db.exec(`
      ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at TIMESTAMPTZ;
      ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS banned_until TIMESTAMPTZ;
      CREATE TABLE IF NOT EXISTS public.migration_id_mappings (
        entity_type TEXT NOT NULL CHECK (char_length(entity_type) <= 64),
        firebase_id TEXT NOT NULL CHECK (char_length(firebase_id) <= 512),
        supabase_id TEXT NOT NULL CHECK (char_length(supabase_id) <= 512),
        checksum TEXT NULL,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        migrated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (entity_type, firebase_id)
      );
      INSERT INTO storage.buckets (id, name, public)
      VALUES ('avatars', 'avatars', false), ('note-media', 'note-media', false)
      ON CONFLICT (id) DO NOTHING;
    `);
    await db.query("SELECT set_config('noted.privileged_op', 'on', false)");
  }

  return {
    isPGlite: true,
    db,
    async query(sql, params = []) {
      await ensureSetup();
      return db.query(sql, params);
    },
    async exec(sql) {
      await ensureSetup();
      return db.exec(sql);
    },
    async getExistingMappings() {
      await ensureSetup();
      const res = await db.query(
        'SELECT entity_type, firebase_id, supabase_id, checksum, metadata FROM public.migration_id_mappings',
      );
      const map = new Map();
      for (const r of res.rows) {
        map.set(`${r.entity_type}:${r.firebase_id}`, {
          checksum: r.checksum,
          supabase_id: r.supabase_id,
          metadata: typeof r.metadata === 'string' ? JSON.parse(r.metadata) : r.metadata,
        });
      }
      return map;
    },
    async upsertMapping({ entity_type, firebase_id, supabase_id, checksum, metadata }) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.migration_id_mappings (entity_type, firebase_id, supabase_id, checksum, metadata, migrated_at)
         VALUES ($1, $2, $3, $4, $5::jsonb, now())
         ON CONFLICT (entity_type, firebase_id) DO UPDATE SET
           supabase_id = EXCLUDED.supabase_id,
           checksum = EXCLUDED.checksum,
           metadata = EXCLUDED.metadata,
           migrated_at = now()`,
        [entity_type, firebase_id, supabase_id, checksum, JSON.stringify(metadata ?? {})],
      );
    },
    async upsertAuthUser({ id, email, name, legacyFirebaseUid, createdAt, emailVerified, disabled }) {
      await ensureSetup();
      const meta = JSON.stringify({
        name,
        ...(legacyFirebaseUid ? { legacy_firebase_uid: legacyFirebaseUid } : {}),
      });
      await db.query(
        `INSERT INTO auth.users (id, email, raw_user_meta_data, created_at, updated_at, email_confirmed_at, banned_until)
         VALUES ($1, $2, $3::jsonb, $4, now(), CASE WHEN $5 THEN now() ELSE NULL END, CASE WHEN $6 THEN now() + interval '100 years' ELSE NULL END)
         ON CONFLICT (id) DO UPDATE SET
           email = EXCLUDED.email,
           raw_user_meta_data = EXCLUDED.raw_user_meta_data,
           email_confirmed_at = EXCLUDED.email_confirmed_at,
           banned_until = EXCLUDED.banned_until,
           updated_at = now()`,
        [id, email, meta, createdAt || new Date().toISOString(), emailVerified, disabled],
      );
    },
    async upsertProfile(p) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.profiles (id, email, name, field_of_study, avatar_path, avatar_url, legacy_firebase_uid, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (id) DO UPDATE SET
           email = EXCLUDED.email,
           name = EXCLUDED.name,
           field_of_study = EXCLUDED.field_of_study,
           avatar_path = EXCLUDED.avatar_path,
           avatar_url = EXCLUDED.avatar_url,
           legacy_firebase_uid = EXCLUDED.legacy_firebase_uid,
           updated_at = EXCLUDED.updated_at`,
        [
          p.id,
          p.email,
          p.name,
          p.fieldOfStudy || '',
          p.avatarPath || null,
          p.avatarUrl || '',
          p.legacyFirebaseUid || null,
          p.createdAt || new Date().toISOString(),
          p.updatedAt || new Date().toISOString(),
        ],
      );
    },
    async upsertSettings(s) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.user_settings (user_id, preferences, timezone_offset_minutes, notes_schema, updated_at)
         VALUES ($1, $2::jsonb, $3, $4, $5)
         ON CONFLICT (user_id) DO UPDATE SET
           preferences = EXCLUDED.preferences,
           timezone_offset_minutes = EXCLUDED.timezone_offset_minutes,
           notes_schema = EXCLUDED.notes_schema,
           updated_at = EXCLUDED.updated_at`,
        [
          s.user_id,
          JSON.stringify(s.preferences ?? {}),
          s.timezone_offset_minutes ?? 0,
          s.notes_schema ?? 2,
          s.updated_at || new Date().toISOString(),
        ],
      );
    },
    async upsertNote(row) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.notes (
           note_id, user_id, owner_name, owner_email, title, content, category, color,
           is_favorite, live_member_ids, live_roles, shared_with_user_ids, pending_shared_with_user_ids,
           source_owner_id, source_note_id, attachments, revision, last_edited_by, deleted_at,
           created_at, updated_at
         ) VALUES (
           $1, $2, $3, $4, $5, $6, $7, $8,
           $9, $10::uuid[], $11::jsonb, $12::uuid[], $13::uuid[],
           $14, $15, $16::jsonb, $17, $18, $19,
           $20, $21
         ) ON CONFLICT (note_id) DO UPDATE SET
           user_id = EXCLUDED.user_id,
           owner_name = EXCLUDED.owner_name,
           owner_email = EXCLUDED.owner_email,
           title = EXCLUDED.title,
           content = EXCLUDED.content,
           category = EXCLUDED.category,
           color = EXCLUDED.color,
           is_favorite = EXCLUDED.is_favorite,
           live_member_ids = EXCLUDED.live_member_ids,
           live_roles = EXCLUDED.live_roles,
           shared_with_user_ids = EXCLUDED.shared_with_user_ids,
           pending_shared_with_user_ids = EXCLUDED.pending_shared_with_user_ids,
           source_owner_id = EXCLUDED.source_owner_id,
           source_note_id = EXCLUDED.source_note_id,
           attachments = EXCLUDED.attachments,
           revision = EXCLUDED.revision,
           last_edited_by = EXCLUDED.last_edited_by,
           deleted_at = EXCLUDED.deleted_at,
           updated_at = EXCLUDED.updated_at`,
        [
          row.note_id,
          row.user_id,
          row.owner_name,
          row.owner_email,
          row.title,
          row.content,
          row.category,
          row.color,
          row.is_favorite,
          toPgUuidArray(row.live_member_ids),
          JSON.stringify(row.live_roles ?? {}),
          toPgUuidArray(row.shared_with_user_ids),
          toPgUuidArray(row.pending_shared_with_user_ids),
          row.source_owner_id,
          row.source_note_id,
          JSON.stringify(row.attachments ?? []),
          row.revision,
          row.last_edited_by,
          row.deleted_at,
          row.created_at,
          row.updated_at,
        ],
      );
    },
    async upsertFavorite(fav) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.user_favorites (user_id, note_id, created_at)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, note_id) DO UPDATE SET created_at = EXCLUDED.created_at`,
        [fav.user_id, fav.note_id, fav.created_at || new Date().toISOString()],
      );
    },
    async upsertConnection(conn) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.connection_requests (
           connection_id, from_user_id, from_name, from_email,
           to_user_id, to_name, to_email, status, created_at, updated_at
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (connection_id) DO UPDATE SET
           from_name = EXCLUDED.from_name,
           from_email = EXCLUDED.from_email,
           to_name = EXCLUDED.to_name,
           to_email = EXCLUDED.to_email,
           status = EXCLUDED.status,
           updated_at = EXCLUDED.updated_at`,
        [
          conn.connection_id,
          conn.from_user_id,
          conn.from_name,
          conn.from_email,
          conn.to_user_id,
          conn.to_name,
          conn.to_email,
          conn.status,
          conn.created_at,
          conn.updated_at,
        ],
      );
    },
    async upsertInvitation(inv) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.user_invitations (user_id, email_hash, email, sent_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, email_hash) DO UPDATE SET
           email = EXCLUDED.email,
           sent_at = EXCLUDED.sent_at`,
        [inv.user_id, inv.email_hash, inv.email, inv.sent_at],
      );
    },
    async upsertNotification(n) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.notifications (
           id, user_id, type, title, body, note_id, actor_id, actor_name, read, email_dispatched, created_at
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (id) DO UPDATE SET
           type = EXCLUDED.type,
           title = EXCLUDED.title,
           body = EXCLUDED.body,
           note_id = EXCLUDED.note_id,
           actor_id = EXCLUDED.actor_id,
           actor_name = EXCLUDED.actor_name,
           read = EXCLUDED.read,
           email_dispatched = EXCLUDED.email_dispatched`,
        [
          n.id,
          n.user_id,
          n.type,
          n.title,
          n.body,
          n.note_id,
          n.actor_id,
          n.actor_name,
          n.read,
          n.email_dispatched,
          n.created_at,
        ],
      );
    },
    async upsertAiRequest(r) {
      await ensureSetup();
      await db.query(`INSERT INTO public.ai_requests (user_id, request_id, cancelled, status, created_at, updated_at, completed_at)
        VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (user_id, request_id) DO UPDATE SET
        cancelled=EXCLUDED.cancelled, status=EXCLUDED.status, updated_at=EXCLUDED.updated_at, completed_at=EXCLUDED.completed_at`,
        [r.user_id,r.request_id,r.cancelled,r.status,r.created_at,r.updated_at,r.completed_at]);
    },
    async upsertChat(c) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.ai_chats (user_id, chat_id, title, scope, created_at, updated_at)
         VALUES ($1, $2, $3, $4::jsonb, $5, $6)
         ON CONFLICT (user_id, chat_id) DO UPDATE SET
           title = EXCLUDED.title,
           scope = EXCLUDED.scope,
           updated_at = EXCLUDED.updated_at`,
        [c.user_id, c.chat_id, c.title, JSON.stringify(c.scope ?? {}), c.created_at, c.updated_at],
      );
    },
    async upsertMessage(m) {
      await ensureSetup();
      await db.query(
        `INSERT INTO public.ai_messages (id, user_id, chat_id, role, text, blocks, sources, intent, fb, created_at)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9, $10)
         ON CONFLICT (id) DO UPDATE SET
           text = EXCLUDED.text,
           blocks = EXCLUDED.blocks,
           sources = EXCLUDED.sources,
           intent = EXCLUDED.intent,
           fb = EXCLUDED.fb`,
        [
          m.id,
          m.user_id,
          m.chat_id,
          m.role,
          m.text,
          m.blocks ? JSON.stringify(m.blocks) : null,
          m.sources ? JSON.stringify(m.sources) : null,
          m.intent,
          m.fb,
          m.created_at,
        ],
      );
    },
    async uploadStorageObject(bucket, targetPath, buffer, { owner, contentType }) {
      await ensureSetup();
      await db.query(
        `INSERT INTO storage.objects (bucket_id, name, owner, metadata)
         VALUES ($1, $2, $3, $4::jsonb)
         ON CONFLICT (bucket_id, name) DO UPDATE SET metadata = EXCLUDED.metadata, created_at = now()`,
        [
          bucket,
          targetPath,
          owner || null,
          JSON.stringify({
            mimetype: contentType || 'application/octet-stream',
            size: buffer ? buffer.length : 0,
            sha256: buffer ? crypto.createHash('sha256').update(buffer).digest('hex') : null,
          }),
        ],
      );
    },
    async deleteStorageObject(bucket, targetPath) {
      await ensureSetup();
      await db.query('DELETE FROM storage.objects WHERE bucket_id = $1 AND name = $2', [
        bucket,
        targetPath,
      ]);
    },
    async deleteAuthUser(id) {
      await ensureSetup();
      await db.query('DELETE FROM auth.users WHERE id = $1', [id]);
    },
  };
}

/**
 * Creates a @supabase/supabase-js admin client executor adapter for production CLI imports.
 */
export function createSupabaseAdminExecutor(supabaseClient) {
  return {
    isSupabaseClient: true,
    client: supabaseClient,
    async getExistingMappings() {
      const data = await selectAllPostgrestRows(
        supabaseClient,
        'migration_id_mappings',
        'entity_type, firebase_id, supabase_id, checksum, metadata',
      );
      const map = new Map();
      for (const r of data || []) {
        map.set(`${r.entity_type}:${r.firebase_id}`, {
          checksum: r.checksum,
          supabase_id: r.supabase_id,
          metadata: r.metadata,
        });
      }
      return map;
    },
    async upsertMapping(mapping) {
      const row = {
        entity_type: mapping.entity_type,
        firebase_id: mapping.firebase_id,
        supabase_id: mapping.supabase_id,
        checksum: mapping.checksum ?? null,
        metadata: mapping.metadata ?? {},
        migrated_at: new Date().toISOString(),
      };
      const { error } = await supabaseClient.from('migration_id_mappings').upsert(row, {
        onConflict: 'entity_type,firebase_id',
      });
      if (error) throw error;
    },
    async upsertAuthUser({ id, email, name, legacyFirebaseUid, emailVerified = false, disabled = false }) {
      const userMetadata = {
        name,
        ...(legacyFirebaseUid ? { legacy_firebase_uid: legacyFirebaseUid } : {}),
      };
      const { error } = await supabaseClient.auth.admin.createUser({
        id,
        email,
        email_confirm: emailVerified,
        ban_duration: disabled ? '876000h' : 'none',
        user_metadata: userMetadata,
      });
      if (error) {
        if (/already\s+(?:been\s+)?(?:exists|registered)/i.test(error.message || '')) {
          const { data, error: lookupError } = await supabaseClient.auth.admin.getUserById(id);
          if (lookupError) throw lookupError;
          if (!data?.user) throw new Error('Existing auth user could not be found by mapped ID');
          if (!emailVerified && data.user.email_confirmed_at) {
            if (disabled) {
              const { error: banError } = await supabaseClient.auth.admin.updateUserById(id, { ban_duration: '876000h' });
              if (banError) throw banError;
            }
            throw new Error('Cannot unconfirm an existing Supabase Auth user; resolve the verification mismatch before importing');
          }
          const { error: updateError } = await supabaseClient.auth.admin.updateUserById(id, {
            email,
            email_confirm: emailVerified,
            ban_duration: disabled ? '876000h' : 'none',
            user_metadata: userMetadata,
          });
          if (updateError) throw updateError;
        } else {
          throw error;
        }
      }
    },
    async upsertProfile(p) {
      const row = {
        id: p.id,
        email: p.email,
        name: p.name,
        field_of_study: p.fieldOfStudy || '',
        avatar_path: p.avatarPath || null,
        avatar_url: p.avatarUrl || '',
        legacy_firebase_uid: p.legacyFirebaseUid || null,
        created_at: p.createdAt || new Date().toISOString(),
        updated_at: p.updatedAt || new Date().toISOString(),
      };
      const { error } = await supabaseClient.from('profiles').upsert(row, { onConflict: 'id' });
      if (error) throw error;
    },
    async upsertSettings(s) {
      const row = {
        user_id: s.user_id,
        preferences: s.preferences ?? {},
        timezone_offset_minutes: s.timezone_offset_minutes ?? 0,
        notes_schema: s.notes_schema ?? 2,
        updated_at: s.updated_at || new Date().toISOString(),
      };
      const { error } = await supabaseClient.from('user_settings').upsert(row, {
        onConflict: 'user_id',
      });
      if (error) throw error;
    },
    async upsertNote(n) {
      const row = {
        note_id: n.note_id,
        user_id: n.user_id,
        owner_name: n.owner_name ?? '',
        owner_email: n.owner_email ?? '',
        title: n.title ?? '',
        content: n.content ?? '',
        category: n.category ?? 'Personal',
        color: n.color ?? 'blue',
        is_favorite: Boolean(n.is_favorite),
        live_member_ids: n.live_member_ids ?? [],
        live_roles: n.live_roles ?? {},
        shared_with_user_ids: n.shared_with_user_ids ?? [],
        pending_shared_with_user_ids: n.pending_shared_with_user_ids ?? [],
        source_owner_id: n.source_owner_id ?? null,
        source_note_id: n.source_note_id ?? null,
        attachments: n.attachments ?? [],
        revision: n.revision ?? 0,
        last_edited_by: n.last_edited_by ?? null,
        deleted_at: n.deleted_at ?? null,
        created_at: n.created_at,
        updated_at: n.updated_at,
      };
      const { error } = await supabaseClient.from('notes').upsert(row, {
        onConflict: 'note_id',
      });
      if (error) throw error;
    },
    async upsertFavorite(fav) {
      const row = {
        user_id: fav.user_id,
        note_id: fav.note_id,
        created_at: fav.created_at || new Date().toISOString(),
      };
      const { error } = await supabaseClient.from('user_favorites').upsert(row, {
        onConflict: 'user_id,note_id',
      });
      if (error) throw error;
    },
    async upsertConnection(conn) {
      const row = {
        connection_id: conn.connection_id,
        from_user_id: conn.from_user_id,
        from_name: conn.from_name ?? '',
        from_email: conn.from_email ?? '',
        to_user_id: conn.to_user_id,
        to_name: conn.to_name ?? '',
        to_email: conn.to_email ?? '',
        status: conn.status,
        created_at: conn.created_at,
        updated_at: conn.updated_at,
      };
      const { error } = await supabaseClient.from('connection_requests').upsert(row, {
        onConflict: 'connection_id',
      });
      if (error) throw error;
    },
    async upsertInvitation(inv) {
      const row = {
        user_id: inv.user_id,
        email_hash: inv.email_hash,
        email: inv.email,
        sent_at: inv.sent_at,
      };
      const { error } = await supabaseClient.from('user_invitations').upsert(row, {
        onConflict: 'user_id,email_hash',
      });
      if (error) throw error;
    },
    async upsertNotification(n) {
      const row = {
        id: n.id,
        user_id: n.user_id,
        type: n.type,
        title: n.title ?? '',
        body: n.body ?? '',
        note_id: n.note_id ?? null,
        actor_id: n.actor_id ?? null,
        actor_name: n.actor_name ?? null,
        read: Boolean(n.read),
        email_dispatched: Boolean(n.email_dispatched),
        created_at: n.created_at,
      };
      const { error } = await supabaseClient.from('notifications').upsert(row, {
        onConflict: 'id',
      });
      if (error) throw error;
    },
    async upsertAiRequest(r) {
      const { error } = await supabaseClient.from('ai_requests').upsert(r, { onConflict: 'user_id,request_id' });
      if (error) throw error;
    },
    async upsertChat(c) {
      const row = {
        user_id: c.user_id,
        chat_id: c.chat_id,
        title: c.title,
        scope: c.scope ?? {},
        created_at: c.created_at,
        updated_at: c.updated_at,
      };
      const { error } = await supabaseClient.from('ai_chats').upsert(row, {
        onConflict: 'user_id,chat_id',
      });
      if (error) throw error;
    },
    async upsertMessage(m) {
      const row = {
        id: m.id,
        user_id: m.user_id,
        chat_id: m.chat_id,
        role: m.role,
        text: m.text ?? null,
        blocks: m.blocks ?? null,
        sources: m.sources ?? null,
        intent: m.intent ?? null,
        fb: m.fb ?? null,
        created_at: m.created_at,
      };
      const { error } = await supabaseClient.from('ai_messages').upsert(row, {
        onConflict: 'id',
      });
      if (error) throw error;
    },
    async uploadStorageObject(bucket, targetPath, buffer, { contentType } = {}) {
      const safeContentType = inferAllowedMimeType(targetPath, contentType, bucket);
      const { error } = await supabaseClient.storage.from(bucket).upload(targetPath, buffer, {
        upsert: true,
        contentType: safeContentType,
      });
      if (error) throw error;
    },
    async deleteStorageObject(bucket, targetPath) {
      const { error } = await supabaseClient.storage.from(bucket).remove([targetPath]);
      if (error) throw error;
    },
    async deleteAuthUser(id) {
      const { error } = await supabaseClient.auth.admin.deleteUser(id);
      if (error && !/not\s*found/i.test(error.message || '')) throw error;
    },
  };
}

/**
 * Programmatically imports a Firebase bundle into the database and storage via an executor.
 */
export async function importBundleToExecutor(
  bundleOrDir,
  executor,
  { dryRun = false, sealRollback = false, onProgress = () => {} } = {},
) {
  let bundle;
  let bundleDir = null;
  if (typeof bundleOrDir === 'string') {
    bundleDir = path.resolve(bundleOrDir);
    bundle = await loadBundleFromDir(bundleDir);
  } else {
    bundle = bundleOrDir;
  }

  if (dryRun && sealRollback) throw new Error('Cannot seal rollback during a dry run');

  // 1. Prepare User Profiles
  const rawAuthUsers = bundle.auth?.users || bundle.authUsers || [];
  const rawFirestoreUsers = bundle.firestore?.users || [];
  const firestoreUserMap = new Map();
  for (const u of rawFirestoreUsers) {
    if (u.id) firestoreUserMap.set(u.id, u);
  }

  const allUserIds = new Set([
    ...rawAuthUsers.map((u) => u.uid).filter(Boolean),
    ...rawFirestoreUsers.map((u) => u.id).filter(Boolean),
  ]);

  const mappedUsers = [];
  const mediaList = [];

  for (const uid of allUserIds) {
    const authUser = rawAuthUsers.find((u) => u.uid === uid) || {};
    const fsUser = firestoreUserMap.get(uid) || {};

    const supabaseUuid = firebaseUidToSupabaseUuid(uid);
    const email = String(authUser.email || fsUser.email || '').trim().toLowerCase();
    const name = String(
      fsUser.name || authUser.displayName || (email ? email.split('@')[0] : '') || 'Noted User',
    ).slice(0, 120);

    let avatarPath = fsUser.avatarPath || null;
    let mappedAvatarPath = null;
    let avatarUrl = '';
    if (avatarPath) {
      mappedAvatarPath = mapStorageObjectPath(avatarPath, firebaseUidToSupabaseUuid);
      avatarUrl = canonicalPrivateMediaUri('avatars', mappedAvatarPath);
      mediaList.push({
        bucket: 'avatars',
        sourcePath: avatarPath,
        targetPath: mappedAvatarPath,
        owner: supabaseUuid,
        contentType: inferAllowedMimeType(mappedAvatarPath, '', 'avatars'),
      });
    } else {
      avatarUrl = String(fsUser.avatarUrl || authUser.photoURL || '').slice(0, 2000);
    }

    const createdAt = normalizeTimestamp(authUser.metadata?.creationTime || fsUser.createdAt);
    const updatedAt = normalizeTimestamp(
      authUser.metadata?.lastSignInTime || fsUser.updatedAt,
      createdAt,
    );

    const userRecord = {
      id: supabaseUuid,
      legacyFirebaseUid: uid,
      email,
      name,
      fieldOfStudy: String(fsUser.fieldOfStudy || '').slice(0, 120),
      avatarPath: mappedAvatarPath,
      avatarUrl,
      createdAt,
      updatedAt,
      emailVerified: authUser.emailVerified === true,
      disabled: authUser.disabled === true,
    };
    userRecord.checksum = computeEntityChecksum({
      uid,
      email,
      name,
      fieldOfStudy: userRecord.fieldOfStudy,
      avatarPath: mappedAvatarPath,
      avatarUrl,
      emailVerified: userRecord.emailVerified,
      disabled: userRecord.disabled,
    });
    mappedUsers.push(userRecord);
  }

  const validUserIds = new Set(mappedUsers.map((u) => u.id));
  const orphanedSkipped = {};
  function recordOrphanSkip(kind) {
    orphanedSkipped[kind] = (orphanedSkipped[kind] || 0) + 1;
  }

  // 2. User Settings
  const mappedSettings = (bundle.firestore?.userSettings || [])
    .map((s) => {
      const userId = firebaseUidToSupabaseUuid(s.userId || s.id);
      if (!validUserIds.has(userId)) {
        recordOrphanSkip('userSettings');
        return null;
      }
      const { userId: ignoredUserId, id: ignoredId, timezoneOffsetMinutes: ignoredTz, notesSchema: ignoredSchema, updatedAt: ignoredUpdated, preferences: nestedPreferences, ...flatPreferences } = s;
      const preferences = nestedPreferences && typeof nestedPreferences === 'object' && !Array.isArray(nestedPreferences) ? nestedPreferences : flatPreferences;
      const timezoneOffsetMinutes = Number.isInteger(s.timezoneOffsetMinutes)
        ? s.timezoneOffsetMinutes
        : 0;
      const notesSchema = Number.isInteger(s.notesSchema) ? s.notesSchema : 2;
      const updatedAt = normalizeTimestamp(s.updatedAt);
      return {
        userId: s.userId || s.id,
        user_id: userId,
        preferences,
        timezone_offset_minutes: timezoneOffsetMinutes,
        notes_schema: notesSchema,
        updated_at: updatedAt,
        checksum: computeEntityChecksum(s),
      };
    })
    .filter(Boolean);

  // 3. Notes & Note Media
  const mappedNotes = (bundle.firestore?.notes || [])
    .map((note) => {
      const noteId = String(note.id || note.note_id);
      const { row, mediaObjects } = mapFirebaseNoteToPostgres(
        noteId,
        note,
        firebaseUidToSupabaseUuid,
      );
      if (!validUserIds.has(row.user_id)) {
        recordOrphanSkip('notes');
        return null;
      }
      // Sanitize nullable provenance FKs referencing deleted accounts
      if (row.source_owner_id && !validUserIds.has(row.source_owner_id)) {
        row.source_owner_id = null;
      }
      if (row.last_edited_by && !validUserIds.has(row.last_edited_by)) {
        row.last_edited_by = null;
      }
      for (const m of mediaObjects) {
        mediaList.push({
          bucket: m.bucket,
          sourcePath: m.sourcePath,
          targetPath: m.targetPath,
          owner: row.user_id,
          contentType: inferAllowedMimeType(m.targetPath, '', m.bucket, m.attachmentType),
        });
      }
      return {
        firebaseId: noteId,
        row,
        checksum: computeEntityChecksum(note),
      };
    })
    .filter(Boolean);

  const validNoteIds = new Set(mappedNotes.map((n) => n.row.note_id));

  // 4. Personal Favorites
  const mappedFavorites = (bundle.firestore?.userFavorites || [])
    .map((fav) => {
      const userId = firebaseUidToSupabaseUuid(fav.userId);
      const noteId = String(fav.noteId);
      if (!validUserIds.has(userId) || !validNoteIds.has(noteId)) {
        recordOrphanSkip('userFavorites');
        return null;
      }
      const createdAt = normalizeTimestamp(fav.createdAt);
      return {
        userId: fav.userId,
        user_id: userId,
        note_id: noteId,
        created_at: createdAt,
        checksum: computeEntityChecksum(fav),
      };
    })
    .filter(Boolean);

  // 5. Connection Requests
  const mappedConnections = (bundle.firestore?.connectionRequests || [])
    .map((conn) => {
      const connId = String(conn.id || conn.connection_id || conn.connectionId);
      const fromUid = conn.fromUserId || conn.senderId || conn.from;
      const toUid = conn.toUserId || conn.receiverId || conn.to;
      const fromUserId = firebaseUidToSupabaseUuid(fromUid);
      const toUserId = firebaseUidToSupabaseUuid(toUid);

      if (fromUserId === toUserId) {
        return null; // Skip self connections
      }
      if (!validUserIds.has(fromUserId) || !validUserIds.has(toUserId)) {
        recordOrphanSkip('connectionRequests');
        return null;
      }

      const status = ['pending', 'accepted', 'rejected'].includes(conn.status)
        ? conn.status
        : 'pending';
      const createdAt = normalizeTimestamp(conn.createdAt);
      const updatedAt = normalizeTimestamp(conn.updatedAt, createdAt);

      return {
        connection_id: connId,
        from_user_id: fromUserId,
        from_name: String(conn.fromName || '').slice(0, 200),
        from_email: String(conn.fromEmail || '').slice(0, 320),
        to_user_id: toUserId,
        to_name: String(conn.toName || '').slice(0, 200),
        to_email: String(conn.toEmail || '').slice(0, 320),
        status,
        created_at: createdAt,
        updated_at: updatedAt,
        checksum: computeEntityChecksum(conn),
      };
    })
    .filter(Boolean);

  // 6. User Invitations
  const mappedInvitations = (bundle.firestore?.userInvitations || [])
    .map((inv) => {
      const userId = firebaseUidToSupabaseUuid(inv.userId);
      if (!validUserIds.has(userId)) {
        recordOrphanSkip('userInvitations');
        return null;
      }
      const emailHash = String(inv.emailHash || inv.id).slice(0, 128);
      const email = String(inv.email || '').slice(0, 320);
      const sentAt = normalizeTimestamp(inv.sentAt || inv.createdAt);
      return {
        user_id: userId,
        email_hash: emailHash,
        email,
        sent_at: sentAt,
        checksum: computeEntityChecksum(inv),
      };
    })
    .filter(Boolean);

  // 7. Activity Notifications
  const mappedNotifications = (bundle.firestore?.notifications || [])
    .map((n) => {
      const id = String(n.id);
      const userId = firebaseUidToSupabaseUuid(n.userId);
      if (!validUserIds.has(userId)) {
        recordOrphanSkip('notifications');
        return null;
      }
      const rawActor = n.actorId ? firebaseUidToSupabaseUuid(n.actorId) : null;
      const actorId = rawActor && validUserIds.has(rawActor) ? rawActor : null;
      const type = ['request', 'copy', 'live', 'system'].includes(n.type) ? n.type : 'system';
      const createdAt = normalizeTimestamp(n.createdAt);
      return {
        id,
        user_id: userId,
        type,
        title: String(n.title || '').slice(0, 300),
        body: String(n.body || '').slice(0, 1000),
        note_id: n.noteId ? String(n.noteId) : null,
        actor_id: actorId,
        actor_name: n.actorName ? String(n.actorName).slice(0, 200) : null,
        read: Boolean(n.read),
        email_dispatched: Boolean(n.emailDispatched),
        created_at: createdAt,
        checksum: computeEntityChecksum(n),
      };
    })
    .filter(Boolean);

  // 8. AI Chats & Messages
  const mappedChats = (bundle.firestore?.aiChats || [])
    .map((c) => {
      const userId = firebaseUidToSupabaseUuid(c.userId);
      if (!validUserIds.has(userId)) {
        recordOrphanSkip('aiChats');
        return null;
      }
      const chatId = String(c.chatId || c.id).slice(0, 120);
      const createdAt = normalizeTimestamp(c.createdAt);
      const updatedAt = normalizeTimestamp(c.updatedAt, createdAt);
      return {
        user_id: userId,
        chat_id: chatId,
        title: String(c.title || 'New chat').slice(0, 200),
        scope: c.scope && typeof c.scope === 'object' ? c.scope : { kind: 'all' },
        created_at: createdAt,
        updated_at: updatedAt,
        checksum: computeEntityChecksum(c),
      };
    })
    .filter(Boolean);

  const mappedRequests = (bundle.firestore?.aiRequests || []).map((r) => {
    const user_id = firebaseUidToSupabaseUuid(r.userId);
    if (!validUserIds.has(user_id)) { recordOrphanSkip('aiRequests'); return null; }
    const created_at = normalizeTimestamp(r.createdAt);
    return { user_id, request_id: String(r.requestId || r.id).slice(0,120), cancelled: Boolean(r.cancelled),
      status: ['running','completed','cancelled','failed'].includes(r.status) ? r.status : 'running',
      created_at, updated_at: normalizeTimestamp(r.updatedAt, created_at),
      completed_at: r.completedAt ? normalizeTimestamp(r.completedAt) : null, checksum: computeEntityChecksum(r) };
  }).filter(Boolean);

  const validChatKeys = new Set(mappedChats.map((c) => `${c.user_id}:${c.chat_id}`));

  const mappedMessages = (bundle.firestore?.aiMessages || [])
    .map((m) => {
      const id = String(m.id);
      const userId = firebaseUidToSupabaseUuid(m.userId);
      const chatId = String(m.chatId || m.chat_id).slice(0, 120);
      if (!validChatKeys.has(`${userId}:${chatId}`)) {
        recordOrphanSkip('aiMessages');
        return null;
      }
      const role = m.role === 'ai' ? 'ai' : 'user';
      const createdAt = normalizeTimestamp(m.createdAt);
      return {
        id,
        user_id: userId,
        chat_id: chatId,
        role,
        text: m.text ? String(m.text).slice(0, 24000) : null,
        blocks: Array.isArray(m.blocks) ? m.blocks : null,
        sources: Array.isArray(m.sources) ? m.sources : null,
        intent: m.intent ? String(m.intent).slice(0, 80) : null,
        fb: m.fb === 'up' || m.fb === 'down' ? m.fb : null,
        created_at: createdAt,
        checksum: computeEntityChecksum(m),
      };
    })
    .filter(Boolean);

  // Also include any media explicitly loaded in bundle.media
  if (Array.isArray(bundle.media)) {
    for (const bMedia of bundle.media) {
      const existing = mediaList.find((m) => m.sourcePath === bMedia.sourcePath);
      if (existing) {
        existing.buffer = bMedia.data || bMedia.buffer;
        existing.contentType = inferAllowedMimeType(
          existing.targetPath,
          bMedia.contentType || existing.contentType,
          existing.bucket,
        );
      } else {
        const mappedTarget = mapStorageObjectPath(bMedia.sourcePath, firebaseUidToSupabaseUuid);
        const bucket = bMedia.sourcePath.includes('/notes/') ? 'note-media' : 'avatars';
        mediaList.push({
          bucket,
          sourcePath: bMedia.sourcePath,
          targetPath: mappedTarget,
          buffer: bMedia.data || bMedia.buffer,
          contentType: inferAllowedMimeType(mappedTarget, bMedia.contentType, bucket),
        });
      }
    }
  }

  for (const media of mediaList) {
    if (!media.buffer) throw new Error(`Migration incomplete: missing media bytes for ${media.sourcePath}`);
  }

  // --- DRY RUN MODE ---
  if (dryRun) {
    onProgress({ stage: 'dry-run', message: 'Dry run completed. ZERO writes performed.' });
    return {
      dryRun: true,
      summary: {
        users: mappedUsers.length,
        userSettings: mappedSettings.length,
        notes: mappedNotes.length,
        userFavorites: mappedFavorites.length,
        connectionRequests: mappedConnections.length,
        userInvitations: mappedInvitations.length,
        notifications: mappedNotifications.length,
        aiChats: mappedChats.length,
        aiMessages: mappedMessages.length,
        aiRequests: mappedRequests.length,
        mediaObjects: mediaList.length,
      },
      orphanedSkipped,
      expectedRows: { users: mappedUsers, settings: mappedSettings, notes: mappedNotes.map(n => n.row), favorites: mappedFavorites, connections: mappedConnections, invitations: mappedInvitations, notifications: mappedNotifications, chats: mappedChats, messages: mappedMessages, requests: mappedRequests },
      mappingPreview: {
        users: mappedUsers.slice(0, 5).map((u) => ({
          legacyFirebaseUid: u.legacyFirebaseUid,
          supabaseUuid: u.id,
          email: u.email,
        })),
        notes: mappedNotes.slice(0, 5).map((n) => ({
          noteId: n.row.note_id,
          userId: n.row.user_id,
          title: n.row.title,
          liveRoles: n.row.live_roles,
        })),
        media: mediaList.slice(0, 5).map((m) => ({
          bucket: m.bucket,
          sourcePath: m.sourcePath,
          targetPath: m.targetPath,
        })),
      },
      errors: [],
    };
  }

  // --- LIVE IMPORT MODE ---
  const existingMappings = await executor.getExistingMappings();
  if (sealRollback && existingMappings.size !== 0) throw new Error('Cannot seal rollback for an existing ledger');
  if (sealRollback) {
    if (executor.isPGlite) await executor.query('SELECT public.audit_assert_migration_target_empty()');
    else { const { error } = await executor.client.rpc('audit_assert_migration_target_empty'); if (error) throw error; }
  }
  const stats = { inserted: {}, skipped: {}, orphanedSkipped };

  async function processRecord(entityType, firebaseId, supabaseId, checksum, metadata, writeFn) {
    const key = `${entityType}:${firebaseId}`;
    const existing = existingMappings.get(key);
    if (existing && existing.checksum === checksum) {
      stats.skipped[entityType] = (stats.skipped[entityType] || 0) + 1;
      return false;
    }
    await writeFn();
    await executor.upsertMapping({
      entity_type: entityType,
      firebase_id: firebaseId,
      supabase_id: supabaseId,
      checksum,
      metadata,
    });
    stats.inserted[entityType] = (stats.inserted[entityType] || 0) + 1;
    existingMappings.set(key, { checksum, supabase_id: supabaseId, metadata });
    return true;
  }

  // 1. Auth Users & Profiles
  onProgress({ stage: 'users', message: `Importing ${mappedUsers.length} users...` });
  for (const u of mappedUsers) {
    await processRecord('user', u.legacyFirebaseUid, u.id, u.checksum, { email: u.email }, async () => {
      await executor.upsertAuthUser({
        id: u.id,
        email: u.email,
        name: u.name,
        legacyFirebaseUid: u.legacyFirebaseUid,
        createdAt: u.createdAt,
        emailVerified: u.emailVerified,
        disabled: u.disabled,
      });
      await executor.upsertProfile(u);
    });
  }

  // 2. User Settings
  onProgress({ stage: 'settings', message: `Importing ${mappedSettings.length} settings...` });
  for (const s of mappedSettings) {
    await processRecord('setting', s.userId, s.user_id, s.checksum, {}, async () => {
      await executor.upsertSettings(s);
    });
  }

  // 3. Notes
  onProgress({ stage: 'notes', message: `Importing ${mappedNotes.length} notes...` });
  for (const n of mappedNotes) {
    await processRecord(
      'note',
      n.firebaseId,
      n.row.note_id,
      n.checksum,
      { title: n.row.title, user_id: n.row.user_id },
      async () => {
        await executor.upsertNote(n.row);
      },
    );
  }

  // 4. Personal Favorites
  onProgress({ stage: 'favorites', message: `Importing ${mappedFavorites.length} favorites...` });
  for (const f of mappedFavorites) {
    const favKey = `${f.user_id}_${f.note_id}`;
    await processRecord('favorite', favKey, favKey, f.checksum, { user_id: f.user_id, note_id: f.note_id }, async () => {
      await executor.upsertFavorite(f);
    });
  }

  // 5. Connection Requests
  onProgress({
    stage: 'connections',
    message: `Importing ${mappedConnections.length} connection requests...`,
  });
  for (const c of mappedConnections) {
    await processRecord(
      'connection',
      c.connection_id,
      c.connection_id,
      c.checksum,
      { from: c.from_user_id, to: c.to_user_id },
      async () => {
        await executor.upsertConnection(c);
      },
    );
  }

  // 6. User Invitations
  onProgress({
    stage: 'invitations',
    message: `Importing ${mappedInvitations.length} invitations...`,
  });
  for (const i of mappedInvitations) {
    const invKey = `${i.user_id}_${i.email_hash}`;
    await processRecord('invitation', invKey, invKey, i.checksum, { user_id: i.user_id }, async () => {
      await executor.upsertInvitation(i);
    });
  }

  // 7. Notifications
  onProgress({
    stage: 'notifications',
    message: `Importing ${mappedNotifications.length} notifications...`,
  });
  for (const notif of mappedNotifications) {
    await processRecord('notification', notif.id, notif.id, notif.checksum, { user_id: notif.user_id }, async () => {
      await executor.upsertNotification(notif);
    });
  }

  // 8. AI Chats & Messages
  onProgress({ stage: 'ai', message: `Importing AI chats & messages...` });
  for (const chat of mappedChats) {
    const chatKey = `${chat.user_id}_${chat.chat_id}`;
    await processRecord('chat', chatKey, chatKey, chat.checksum, { user_id: chat.user_id }, async () => {
      await executor.upsertChat(chat);
    });
  }

  for (const msg of mappedMessages) {
    await processRecord('message', msg.id, msg.id, msg.checksum, { chat_id: msg.chat_id }, async () => {
      await executor.upsertMessage(msg);
    });
  }

  for (const request of mappedRequests) {
    const { checksum, ...row } = request;
    const key = `${row.user_id}_${row.request_id}`;
    await processRecord('ai_request', key, key, checksum, { user_id: row.user_id, request_id: row.request_id }, () => executor.upsertAiRequest(row));
  }

  // 9. Storage Media
  onProgress({ stage: 'media', message: `Uploading ${mediaList.length} storage objects...` });
  for (const m of mediaList) {
    let buf = m.buffer;
    if (!buf && bundleDir) {
      try {
        const candidate = path.join(bundleDir, 'media', m.sourcePath);
        buf = await fs.readFile(candidate);
      } catch {}
    }
    if (!buf) {
      stats.skipped.mediaMissingBytes = (stats.skipped.mediaMissingBytes || 0) + 1;
      continue;
    }
    const mediaChecksum = crypto.createHash('sha256').update(buf).digest('hex');
    const mediaKey = `${m.bucket}/${m.targetPath}`;

    await processRecord('media', m.sourcePath, mediaKey, mediaChecksum, { bucket: m.bucket, targetPath: m.targetPath }, async () => {
      await executor.uploadStorageObject(m.bucket, m.targetPath, buf, {
        owner: m.owner,
        contentType: m.contentType,
      });
    });
  }

  if (sealRollback) {
    if (Object.keys(orphanedSkipped).length) throw new Error('Cannot seal rollback when records were skipped');
    const { validateMigratedBundle, createPGliteReader, createSupabaseAdminReader } = await import('./validate_migration.mjs');
    let snapshot;
    if (executor.isPGlite) {
      const response = await executor.query('SELECT public.audit_get_migration_rollback_state() AS state');
      snapshot = response.rows[0].state;
    } else {
      const { data, error } = await executor.client.rpc('audit_get_migration_rollback_state');
      if (error) throw error;
      snapshot = data;
    }
    const expectedCounts = {
      profiles: mappedUsers.length, user_settings: mappedUsers.length,
      notes: mappedNotes.length, user_favorites: mappedFavorites.length,
      connection_requests: mappedConnections.length, user_invitations: mappedInvitations.length,
      notifications: mappedNotifications.length, ai_chats: mappedChats.length,
      ai_messages: mappedMessages.length, ai_requests: mappedRequests.length,
      migration_id_mappings: existingMappings.size,
      note_presence: 0, note_activity_windows: 0, rate_limits: 0,
      note_deletion_tombstones: 0, deleting_accounts: 0, audit_copy_cleanup_reservations: 0,
      audit_copy_sweeps: 0, audit_email_cursor: 0,
    };
    for (const [table, count] of Object.entries(expectedCounts)) {
      if (!Array.isArray(snapshot?.[table]) || snapshot[table].length !== count)
        throw new Error(`Cannot seal rollback: unexpected ${table} row count`);
    }
    const authIds = mappedUsers.map(u => u.id).sort();
    if (!Array.isArray(snapshot.auth_users) || !isDeepStrictEqual(snapshot.auth_users.map(u => u.id).sort(), authIds))
      throw new Error('Cannot seal rollback: unexpected auth users');
    const expectedMedia = [...existingMappings.entries()]
      .filter(([key]) => key.startsWith('media:'))
      .map(([, mapping]) => mapping.supabase_id).sort();
    if (!Array.isArray(snapshot.storage_objects) || !isDeepStrictEqual(snapshot.storage_objects.map(o => `${o.bucket_id}/${o.name}`).sort(), expectedMedia))
      throw new Error('Cannot seal rollback: unexpected storage objects');
    for (const row of snapshot.migration_id_mappings) {
      const expected = existingMappings.get(`${row.entity_type}:${row.firebase_id}`);
      if (!expected || expected.supabase_id !== row.supabase_id || expected.checksum !== row.checksum ||
          !isDeepStrictEqual(expected.metadata || {}, row.metadata || {}))
        throw new Error('Cannot seal rollback: unexpected migration mapping');
    }
    const mappedSettingIds = new Set(mappedSettings.map(s => s.user_id));
    const mappedUserIds = new Set(mappedUsers.map(u => u.id));
    for (const setting of snapshot.user_settings) {
      if (!mappedUserIds.has(setting.user_id)) throw new Error('Cannot seal rollback: unexpected default settings owner');
      if (!mappedSettingIds.has(setting.user_id) &&
          (!isDeepStrictEqual(setting.preferences, {}) || setting.timezone_offset_minutes !== 0 || setting.notes_schema !== 2))
        throw new Error('Cannot seal rollback: unexpected default settings');
    }
    const reader = executor.isPGlite ? createPGliteReader(executor.db) : createSupabaseAdminReader(executor.client);
    const snapshotTables = {
      getProfiles:'profiles', getUserSettings:'user_settings', getNotes:'notes',
      getUserFavorites:'user_favorites', getConnectionRequests:'connection_requests',
      getUserInvitations:'user_invitations', getNotifications:'notifications',
      getAiChats:'ai_chats', getAiMessages:'ai_messages', getAiRequests:'ai_requests',
      getMappings:'migration_id_mappings',
    };
    for (const [method, table] of Object.entries(snapshotTables)) reader[method] = async () => snapshot[table];
    const validation = await validateMigratedBundle(bundle, reader);
    if (!validation.ok) throw new Error(`Cannot seal rollback: validation failed: ${validation.errors.join('; ')}`);
    if (executor.isPGlite) await executor.query('SELECT public.audit_seal_migration_rollback($1::jsonb)', [JSON.stringify(snapshot)]);
    else { const { error } = await executor.client.rpc('audit_seal_migration_rollback', {p_expected_state:snapshot}); if (error) throw error; }

  }
  onProgress({ stage: 'done', message: 'Migration import completed successfully.' });
  return {
    dryRun: false,
    stats,
    errors: [],
  };
}

/**
 * CLI execution entrypoint
 */
async function runCli() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.dryRun && (!args.supabaseUrl || !args.serviceRoleKey)) {
    console.error(
      'Error: --supabase-url and --service-role-key are required for live imports (or run with --dry-run).',
    );
    process.exit(1);
  }

  let executor;
  if (args.dryRun && !args.supabaseUrl) {
    // For standalone dry-run preview, a dummy executor suffices
    executor = {
      async getExistingMappings() {
        return new Map();
      },
    };
  } else {
    const { createClient } = await import('@supabase/supabase-js');
    const supabase = createClient(args.supabaseUrl, args.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    executor = createSupabaseAdminExecutor(supabase);
  }

  console.log(`Starting migration import from ${args.bundle} (dryRun: ${args.dryRun})...`);
  const result = await importBundleToExecutor(args.bundle, executor, {
    dryRun: args.dryRun,
    sealRollback: args.sealRollback,
    onProgress: ({ stage, message }) => console.log(`[${stage}] ${message}`),
  });

  console.log('Result:');
  console.log(JSON.stringify(result, null, 2));
}

const currentFileUrl = import.meta.url;
const executedFileUrl = pathToFileURL(path.resolve(process.argv[1] || '')).href;
if (currentFileUrl === executedFileUrl) {
  runCli().catch((err) => {
    console.error('Fatal import error:', err);
    process.exit(1);
  });
}
