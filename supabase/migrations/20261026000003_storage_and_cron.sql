-- =============================================================================
-- Noted Supabase Migration 003: Private Storage Buckets, Media RLS & Scheduling
-- Replaces Firebase Storage (`storage.rules`) and Cloud Scheduler cron triggers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Safe Path Segment & UUID Parsing Helpers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.storage_path_segment(p_name TEXT, p_index INT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT split_part(trim(leading '/' FROM COALESCE(p_name, '')), '/', p_index);
$$;

CREATE OR REPLACE FUNCTION public.try_parse_uuid(p_value TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_value IS NULL OR p_value = '' THEN
    RETURN NULL;
  END IF;
  RETURN p_value::uuid;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. Private Buckets (`avatars` and `note-media`) — NEVER public
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'storage' AND table_name = 'buckets'
  ) THEN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES
      ('avatars', 'avatars', false, 5242880, ARRAY['image/*']),
      ('note-media', 'note-media', false, 31457280, ARRAY['image/*', 'audio/*'])
    ON CONFLICT (id) DO UPDATE SET
      public = false,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Storage Object RLS Policies (`storage.objects`)
--    - `avatars`: `users/{uid}/{fileName}`
--    - `note-media`: `users/{uploaderUid}/notes/{noteId}/{fileName}`
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'storage' AND table_name = 'objects'
  ) THEN
    -- Avatars: readable by self, connected peers, or note co-members
    EXECUTE 'DROP POLICY IF EXISTS avatars_select_authorized ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY avatars_select_authorized ON storage.objects
        FOR SELECT TO authenticated
        USING (
          bucket_id = 'avatars'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 3) <> ''
          AND public.storage_path_segment(name, 4) = ''
          AND public.can_view_peer_profile(
            public.try_parse_uuid(public.storage_path_segment(name, 2))
          )
        )
    $pol$;

    EXECUTE 'DROP POLICY IF EXISTS avatars_insert_own ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY avatars_insert_own ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (
          bucket_id = 'avatars'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) <> ''
          AND public.storage_path_segment(name, 4) = ''
        )
    $pol$;

    EXECUTE 'DROP POLICY IF EXISTS avatars_update_own ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY avatars_update_own ON storage.objects
        FOR UPDATE TO authenticated
        USING (
          bucket_id = 'avatars'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) <> ''
          AND public.storage_path_segment(name, 4) = ''
        )
        WITH CHECK (
          bucket_id = 'avatars'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) <> ''
          AND public.storage_path_segment(name, 4) = ''
        )
    $pol$;

    EXECUTE 'DROP POLICY IF EXISTS avatars_delete_own ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY avatars_delete_own ON storage.objects
        FOR DELETE TO authenticated
        USING (
          bucket_id = 'avatars'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) <> ''
          AND public.storage_path_segment(name, 4) = ''
        )
    $pol$;

    -- Note Media: readable by note owner & active live collaborators (`is_note_member`)
    EXECUTE 'DROP POLICY IF EXISTS note_media_select_member ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY note_media_select_member ON storage.objects
        FOR SELECT TO authenticated
        USING (
          bucket_id = 'note-media'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 3) = 'notes'
          AND public.storage_path_segment(name, 5) <> ''
          AND public.storage_path_segment(name, 6) = ''
          AND public.is_note_member(public.storage_path_segment(name, 4))
        )
    $pol$;

    -- Note Media: writable by note owner or active live editor into their own uploader prefix
    EXECUTE 'DROP POLICY IF EXISTS note_media_insert_editor ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY note_media_insert_editor ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (
          bucket_id = 'note-media'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) = 'notes'
          AND public.storage_path_segment(name, 5) <> ''
          AND public.storage_path_segment(name, 6) = ''
          AND public.is_note_editor(public.storage_path_segment(name, 4))
        )
    $pol$;

    EXECUTE 'DROP POLICY IF EXISTS note_media_update_editor ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY note_media_update_editor ON storage.objects
        FOR UPDATE TO authenticated
        USING (
          bucket_id = 'note-media'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) = 'notes'
          AND public.storage_path_segment(name, 5) <> ''
          AND public.storage_path_segment(name, 6) = ''
          AND public.is_note_editor(public.storage_path_segment(name, 4))
        )
        WITH CHECK (
          bucket_id = 'note-media'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 2) = auth.uid()::text
          AND public.storage_path_segment(name, 3) = 'notes'
          AND public.storage_path_segment(name, 5) <> ''
          AND public.storage_path_segment(name, 6) = ''
          AND public.is_note_editor(public.storage_path_segment(name, 4))
        )
    $pol$;

    EXECUTE 'DROP POLICY IF EXISTS note_media_delete_editor_or_owner ON storage.objects';
    EXECUTE $pol$
      CREATE POLICY note_media_delete_editor_or_owner ON storage.objects
        FOR DELETE TO authenticated
        USING (
          bucket_id = 'note-media'
          AND public.storage_path_segment(name, 1) = 'users'
          AND public.storage_path_segment(name, 3) = 'notes'
          AND public.storage_path_segment(name, 5) <> ''
          AND public.storage_path_segment(name, 6) = ''
          AND (
            public.storage_path_segment(name, 2) = auth.uid()::text
            OR public.is_note_owner(public.storage_path_segment(name, 4))
          )
          AND public.is_note_editor(public.storage_path_segment(name, 4))
        )
    $pol$;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Database Housekeeping & `pg_cron` + `pg_net` Schedule Registration
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_rows()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_presence_deleted INT;
  v_windows_deleted INT;
BEGIN
  IF NOT public.is_privileged_context() THEN
    RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.note_presence
   WHERE expires_at < now() - interval '1 hour';
  GET DIAGNOSTICS v_presence_deleted = ROW_COUNT;

  DELETE FROM public.note_activity_windows
   WHERE created_at < now() - interval '7 days';
  GET DIAGNOSTICS v_windows_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'presenceDeleted', v_presence_deleted,
    'activityWindowsDeleted', v_windows_deleted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_ephemeral_rows() FROM PUBLIC, anon, authenticated;

-- Admin helper to wire Supabase `pg_cron` + `pg_net` -> `scheduled-maintenance` Edge Function.
-- Run once in the Supabase SQL Editor after setting secrets:
--   SELECT public.configure_noted_schedules('https://<project-ref>.supabase.co', '<CRON_SECRET>');
CREATE OR REPLACE FUNCTION public.configure_noted_schedules(
  p_project_url TEXT,
  p_cron_secret TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_endpoint TEXT := rtrim(p_project_url, '/') || '/functions/v1/scheduled-maintenance';
BEGIN
  IF NOT public.is_privileged_context() THEN
    RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';
  END IF;

  CREATE EXTENSION IF NOT EXISTS pg_cron;
  CREATE EXTENSION IF NOT EXISTS pg_net;

  -- Unschedule existing jobs if re-running idempotently
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'noted-hourly-maintenance') THEN
    PERFORM cron.unschedule('noted-hourly-maintenance');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'noted-daily-trash-purge') THEN
    PERFORM cron.unschedule('noted-daily-trash-purge');
  END IF;

  -- Hourly: weekly recap (Sunday 09:00 local user time) + pending activity emails + ephemeral cleanup
  PERFORM cron.schedule(
    'noted-hourly-maintenance',
    '0 * * * *',
    format(
      $cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', %L
        ),
        body := '{"job":"hourly"}'::jsonb
      );
      $cmd$,
      v_endpoint,
      p_cron_secret
    )
  );

  -- Daily 03:00 UTC: purge notes soft-deleted >= 30 days ago and their private Storage objects
  PERFORM cron.schedule(
    'noted-daily-trash-purge',
    '0 3 * * *',
    format(
      $cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', %L
        ),
        body := '{"job":"purge"}'::jsonb
      );
      $cmd$,
      v_endpoint,
      p_cron_secret
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.configure_noted_schedules(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
