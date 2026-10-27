import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const requireFromTools = createRequire(
  path.resolve(__dirname, '..', '..', 'tools', 'migration', 'package.json'),
);
const { PGlite } = requireFromTools('@electric-sql/pglite');
const migrationsDir = path.resolve(__dirname, '..', 'migrations');

/**
 * Creates an in-memory PostgreSQL instance simulating Supabase's `auth` and
 * `storage` schemas + JWT session claims, then runs all production migrations.
 */
export async function createSupabaseTestDb() {
  const db = new PGlite();

  await db.exec(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN BYPASSRLS;
      END IF;
    END;
    $$;

    CREATE SCHEMA IF NOT EXISTS auth;
    GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

    CREATE TABLE IF NOT EXISTS auth.users (
      id UUID PRIMARY KEY,
      email TEXT UNIQUE,
      encrypted_password TEXT,
      raw_user_meta_data JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE OR REPLACE FUNCTION auth.uid()
    RETURNS UUID
    LANGUAGE sql
    STABLE
    AS $$
      SELECT NULLIF(
        COALESCE(
          current_setting('request.jwt.claim.sub', true),
          (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
        ),
        ''
      )::uuid;
    $$;

    CREATE OR REPLACE FUNCTION auth.role()
    RETURNS TEXT
    LANGUAGE sql
    STABLE
    AS $$
      SELECT COALESCE(
        NULLIF(current_setting('request.jwt.claim.role', true), ''),
        (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
        current_user
      );
    $$;

    GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC, anon, authenticated, service_role;
    GRANT EXECUTE ON FUNCTION auth.role() TO PUBLIC, anon, authenticated, service_role;

    CREATE SCHEMA IF NOT EXISTS storage;
    GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

    CREATE TABLE IF NOT EXISTS storage.buckets (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      public BOOLEAN NOT NULL DEFAULT false,
      file_size_limit BIGINT NULL,
      allowed_mime_types TEXT[] NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS storage.objects (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      bucket_id TEXT NOT NULL REFERENCES storage.buckets(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      owner UUID NULL,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (bucket_id, name)
    );

    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
    GRANT ALL ON ALL TABLES IN SCHEMA storage TO service_role;

    CREATE PUBLICATION supabase_realtime;
  `);

  const files = (await fs.readdir(migrationsDir))
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const sql = await fs.readFile(path.join(migrationsDir, file), 'utf8');
    await db.exec(sql);
  }

  /**
   * Execute a callback inside a transaction impersonating a Supabase JWT user.
   */
  async function asUser(userId, fn) {
    return db.transaction(async (tx) => {
      const claims = JSON.stringify({
        sub: userId,
        role: 'authenticated',
      });
      await tx.query(`SELECT set_config('request.jwt.claims', $1, true)`, [claims]);
      await tx.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [userId]);
      await tx.query(`SELECT set_config('request.jwt.claim.role', 'authenticated', true)`);
      await tx.exec(`SET LOCAL ROLE authenticated`);
      return fn(tx);
    });
  }

  async function asAnon(fn) {
    return db.transaction(async (tx) => {
      await tx.query(`SELECT set_config('request.jwt.claims', '{"role":"anon"}', true)`);
      await tx.query(`SELECT set_config('request.jwt.claim.sub', '', true)`);
      await tx.query(`SELECT set_config('request.jwt.claim.role', 'anon', true)`);
      await tx.exec(`SET LOCAL ROLE anon`);
      return fn(tx);
    });
  }

  async function asService(fn) {
    return db.transaction(async (tx) => {
      await tx.query(`SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true)`);
      await tx.query(`SELECT set_config('request.jwt.claim.role', 'service_role', true)`);
      await tx.exec(`SET LOCAL ROLE service_role`);
      return fn(tx);
    });
  }

  async function createAuthUser({ id, email, name, legacyFirebaseUid = null }) {
    await db.query(
      `INSERT INTO auth.users (id, email, raw_user_meta_data)
       VALUES ($1, $2, $3::jsonb)`,
      [
        id,
        email,
        JSON.stringify({
          name,
          ...(legacyFirebaseUid ? { legacy_firebase_uid: legacyFirebaseUid } : {}),
        }),
      ],
    );
  }

  return { db, asUser, asAnon, asService, createAuthUser };
}
