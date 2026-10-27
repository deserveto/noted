-- =============================================================================
-- Noted Supabase Migration 001: Initial Application Schema, Constraints & Indexes
-- Replaces Cloud Firestore collections & Firebase Auth user profile bootstrap
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pgcrypto') THEN
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 1. User Profiles (`users/{uid}`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL DEFAULT '' CHECK (char_length(name) <= 120),
  field_of_study TEXT NOT NULL DEFAULT '' CHECK (char_length(field_of_study) <= 120),
  avatar_path TEXT NULL CHECK (avatar_path IS NULL OR char_length(avatar_path) <= 500),
  avatar_url TEXT NOT NULL DEFAULT '' CHECK (char_length(avatar_url) <= 2000),
  legacy_firebase_uid TEXT UNIQUE NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_email_lower
  ON public.profiles (lower(email));

-- -----------------------------------------------------------------------------
-- 2. Private User Settings (`users/{uid}/private/settings`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  preferences JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(preferences) = 'object'),
  timezone_offset_minutes INT NOT NULL DEFAULT 0
    CHECK (timezone_offset_minutes BETWEEN -840 AND 840),
  notes_schema INT NOT NULL DEFAULT 2,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 3. Notes (`notes/{noteId}`)
-- `note_id` is TEXT so existing 20-char Firestore IDs & native deep links
-- (`noted://app/notes/<id>`) survive migration without rewriting links.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notes (
  note_id TEXT PRIMARY KEY DEFAULT replace(gen_random_uuid()::text, '-', ''),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  owner_name TEXT NOT NULL DEFAULT '' CHECK (char_length(owner_name) <= 200),
  owner_email TEXT NOT NULL DEFAULT '' CHECK (char_length(owner_email) <= 320),
  title TEXT NOT NULL DEFAULT '' CHECK (char_length(title) <= 1000),
  content TEXT NOT NULL DEFAULT '' CHECK (char_length(content) <= 1000000),
  category TEXT NOT NULL DEFAULT 'Personal' CHECK (char_length(category) <= 200),
  color TEXT NOT NULL DEFAULT 'blue'
    CHECK (color IN ('blue', 'pink', 'mint', 'yellow', 'peach', 'lav')),
  is_favorite BOOLEAN NOT NULL DEFAULT false,
  live_member_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
  live_roles JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(live_roles) = 'object'),
  shared_with_user_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
  pending_shared_with_user_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
  source_owner_id UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  source_note_id TEXT NULL,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(attachments) = 'array' AND jsonb_array_length(attachments) <= 100),
  revision INT NOT NULL DEFAULT 0 CHECK (revision >= 0),
  last_edited_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  deleted_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notes_owner_active_updated
  ON public.notes (user_id, updated_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notes_owner_deleted
  ON public.notes (user_id, deleted_at DESC)
  WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notes_deleted_purge
  ON public.notes (deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notes_live_members_gin
  ON public.notes USING GIN (live_member_ids)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notes_pending_shares_gin
  ON public.notes USING GIN (pending_shared_with_user_ids)
  WHERE deleted_at IS NULL;

-- -----------------------------------------------------------------------------
-- 4. Per-User Favorites (`users/{uid}/favorites/{noteId}`)
-- Allows collaborators to star shared live notes privately without mutating
-- the owner's `notes.is_favorite` flag.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_favorites (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  note_id TEXT NOT NULL REFERENCES public.notes(note_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, note_id)
);

CREATE INDEX IF NOT EXISTS idx_user_favorites_note
  ON public.user_favorites (note_id);

-- -----------------------------------------------------------------------------
-- 5. Live Collaborator Presence (`notes/{noteId}/presence/{uid}`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.note_presence (
  note_id TEXT NOT NULL REFERENCES public.notes(note_id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT '' CHECK (char_length(name) <= 200),
  typing BOOLEAN NOT NULL DEFAULT false,
  expires_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (note_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_note_presence_expires
  ON public.note_presence (note_id, expires_at);

-- -----------------------------------------------------------------------------
-- 6. Live Edit Activity Deduplication Windows (`notes/{noteId}/activityWindows`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.note_activity_windows (
  note_id TEXT NOT NULL REFERENCES public.notes(note_id) ON DELETE CASCADE,
  window_key TEXT NOT NULL CHECK (char_length(window_key) <= 120),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (note_id, window_key)
);

-- -----------------------------------------------------------------------------
-- 7. Connection Requests (`connection_requests/{connectionId}`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.connection_requests (
  connection_id TEXT PRIMARY KEY DEFAULT replace(gen_random_uuid()::text, '-', ''),
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  from_name TEXT NOT NULL DEFAULT '' CHECK (char_length(from_name) <= 200),
  from_email TEXT NOT NULL DEFAULT '' CHECK (char_length(from_email) <= 320),
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_name TEXT NOT NULL DEFAULT '' CHECK (char_length(to_name) <= 200),
  to_email TEXT NOT NULL DEFAULT '' CHECK (char_length(to_email) <= 320),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_no_self_connection CHECK (from_user_id <> to_user_id)
);

-- Prevent duplicate active (pending or accepted) connections in either direction
CREATE UNIQUE INDEX IF NOT EXISTS idx_connection_unique_active_pair
  ON public.connection_requests (
    LEAST(from_user_id, to_user_id),
    GREATEST(from_user_id, to_user_id)
  )
  WHERE status IN ('pending', 'accepted');

CREATE INDEX IF NOT EXISTS idx_connections_from_updated
  ON public.connection_requests (from_user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_connections_to_updated
  ON public.connection_requests (to_user_id, updated_at DESC);

-- -----------------------------------------------------------------------------
-- 8. Outbound Email Invitations (`users/{uid}/invitations/{emailHash}`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_invitations (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_hash TEXT NOT NULL CHECK (char_length(email_hash) <= 128),
  email TEXT NOT NULL CHECK (char_length(email) <= 320),
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, email_hash)
);

CREATE INDEX IF NOT EXISTS idx_user_invitations_sent
  ON public.user_invitations (user_id, sent_at DESC);

-- -----------------------------------------------------------------------------
-- 9. Activity Notifications (`users/{uid}/notifications/{id}`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id TEXT PRIMARY KEY DEFAULT replace(gen_random_uuid()::text, '-', ''),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('request', 'copy', 'live', 'system')),
  title TEXT NOT NULL CHECK (char_length(title) <= 300),
  body TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 1000),
  note_id TEXT NULL,
  actor_id UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_name TEXT NULL CHECK (actor_name IS NULL OR char_length(actor_name) <= 200),
  read BOOLEAN NOT NULL DEFAULT false,
  email_dispatched BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON public.notifications (user_id)
  WHERE read = false;

CREATE INDEX IF NOT EXISTS idx_notifications_pending_email
  ON public.notifications (created_at)
  WHERE email_dispatched = false;

-- -----------------------------------------------------------------------------
-- 10. AI Requests, Chats & Messages (`users/{uid}/aiRequests`, `chats`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_requests (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id TEXT NOT NULL CHECK (char_length(request_id) <= 120),
  cancelled BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'running'
    CHECK (status IN ('running', 'completed', 'cancelled', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ NULL,
  PRIMARY KEY (user_id, request_id)
);

CREATE TABLE IF NOT EXISTS public.ai_chats (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  chat_id TEXT NOT NULL CHECK (char_length(chat_id) <= 120),
  title TEXT NOT NULL DEFAULT 'New chat' CHECK (char_length(title) <= 200),
  scope JSONB NOT NULL DEFAULT '{"kind":"all"}'::jsonb
    CHECK (jsonb_typeof(scope) = 'object'),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, chat_id)
);

CREATE INDEX IF NOT EXISTS idx_ai_chats_user_updated
  ON public.ai_chats (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.ai_messages (
  id TEXT PRIMARY KEY DEFAULT replace(gen_random_uuid()::text, '-', ''),
  user_id UUID NOT NULL,
  chat_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'ai')),
  text TEXT NULL CHECK (text IS NULL OR char_length(text) <= 24000),
  blocks JSONB NULL CHECK (blocks IS NULL OR jsonb_typeof(blocks) = 'array'),
  sources JSONB NULL CHECK (sources IS NULL OR jsonb_typeof(sources) = 'array'),
  intent TEXT NULL CHECK (intent IS NULL OR char_length(intent) <= 80),
  fb TEXT NULL CHECK (fb IS NULL OR fb IN ('up', 'down')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (user_id, chat_id)
    REFERENCES public.ai_chats(user_id, chat_id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ai_messages_chat_created
  ON public.ai_messages (user_id, chat_id, created_at ASC);

-- -----------------------------------------------------------------------------
-- 11. Server-Side Rate Limits (`rate_limits/{key}`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rate_limits (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation TEXT NOT NULL CHECK (char_length(operation) <= 64),
  count INT NOT NULL DEFAULT 0 CHECK (count >= 0),
  reset_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, operation)
);

-- -----------------------------------------------------------------------------
-- 12. Migration ID Mappings & Checksums (Server-Only Audit / Rollback Ledger)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.migration_id_mappings (
  entity_type TEXT NOT NULL CHECK (char_length(entity_type) <= 64),
  firebase_id TEXT NOT NULL CHECK (char_length(firebase_id) <= 512),
  supabase_id TEXT NOT NULL CHECK (char_length(supabase_id) <= 512),
  checksum TEXT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  migrated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_type, firebase_id)
);

CREATE INDEX IF NOT EXISTS idx_migration_mappings_supabase_id
  ON public.migration_id_mappings (entity_type, supabase_id);

-- -----------------------------------------------------------------------------
-- 13. Auth Lifecycle Triggers (`auth.users` -> `public.profiles` & `user_settings`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT;
  v_name TEXT;
  v_field TEXT;
  v_legacy_uid TEXT;
BEGIN
  PERFORM set_config('noted.privileged_op', 'on', true);
  v_email := lower(trim(COALESCE(NEW.email, '')));
  v_name := left(
    trim(COALESCE(
      NULLIF(NEW.raw_user_meta_data ->> 'name', ''),
      NULLIF(split_part(v_email, '@', 1), ''),
      'Noted User'
    )),
    120
  );
  v_field := left(trim(COALESCE(NEW.raw_user_meta_data ->> 'field_of_study', '')), 120);
  v_legacy_uid := NULLIF(trim(COALESCE(NEW.raw_user_meta_data ->> 'legacy_firebase_uid', '')), '');

  INSERT INTO public.profiles (id, email, name, field_of_study, legacy_firebase_uid, created_at, updated_at)
  VALUES (
    NEW.id,
    v_email,
    v_name,
    v_field,
    v_legacy_uid,
    COALESCE(NEW.created_at, now()),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = CASE WHEN public.profiles.name = '' THEN EXCLUDED.name ELSE public.profiles.name END,
    legacy_firebase_uid = COALESCE(public.profiles.legacy_firebase_uid, EXCLUDED.legacy_firebase_uid),
    updated_at = now();

  INSERT INTO public.user_settings (user_id, preferences, notes_schema, updated_at)
  VALUES (NEW.id, '{}'::jsonb, 2, now())
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM set_config('noted.privileged_op', 'off', true);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

CREATE OR REPLACE FUNCTION public.sync_auth_user_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    PERFORM set_config('noted.privileged_op', 'on', true);
    UPDATE public.profiles
       SET email = lower(trim(COALESCE(NEW.email, ''))),
           updated_at = now()
     WHERE id = NEW.id;
    PERFORM set_config('noted.privileged_op', 'off', true);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_email_updated ON auth.users;
CREATE TRIGGER on_auth_user_email_updated
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_auth_user_email();
