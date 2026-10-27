-- =============================================================================
-- Noted Supabase Migration 002: Row Level Security, Column Guards, RPCs & Triggers
-- Enforces ownership, live collaboration roles, personal favorites/settings/chats,
-- revision-checked concurrency, and collaborator activity notifications.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Privileged Context & Access Helper Predicates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_privileged_context()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    COALESCE(current_setting('noted.privileged_op', true), '') = 'on'
    OR COALESCE(auth.role(), '') = 'service_role'
    OR (
      session_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin')
      AND COALESCE(auth.role(), '') NOT IN ('anon', 'authenticated')
    );
$$;

CREATE OR REPLACE FUNCTION public.is_note_owner(p_note_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.notes n
     WHERE n.note_id = p_note_id
       AND n.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_note_member(p_note_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.notes n
     WHERE n.note_id = p_note_id
       AND (
         n.user_id = auth.uid()
         OR (
           n.deleted_at IS NULL
           AND auth.uid() = ANY(n.live_member_ids)
         )
       )
  );
$$;

CREATE OR REPLACE FUNCTION public.is_note_editor(p_note_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.notes n
     WHERE n.note_id = p_note_id
       AND (
         n.user_id = auth.uid()
         OR (
           n.deleted_at IS NULL
           AND auth.uid() = ANY(n.live_member_ids)
           AND (n.live_roles ->> (auth.uid()::text)) = 'edit'
         )
       )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_peer_profile(p_target_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND (
      p_target_id = auth.uid()
      OR EXISTS (
        SELECT 1
          FROM public.connection_requests c
         WHERE (c.from_user_id = auth.uid() AND c.to_user_id = p_target_id)
            OR (c.to_user_id = auth.uid() AND c.from_user_id = p_target_id)
      )
      OR EXISTS (
        SELECT 1
          FROM public.notes n
         WHERE n.deleted_at IS NULL
           AND (
             n.user_id = auth.uid()
             OR auth.uid() = ANY(n.live_member_ids)
             OR auth.uid() = ANY(n.pending_shared_with_user_ids)
           )
           AND (
             n.user_id = p_target_id
             OR p_target_id = ANY(n.live_member_ids)
             OR p_target_id = ANY(n.pending_shared_with_user_ids)
           )
      )
    );
$$;

-- -----------------------------------------------------------------------------
-- 2. Enable RLS Across Every Application Table
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_activity_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.connection_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_id_mappings ENABLE ROW LEVEL SECURITY;

-- Server-only tables: revoke direct anon/authenticated table access
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.profiles,
  public.user_settings,
  public.notes,
  public.user_favorites,
  public.note_presence,
  public.connection_requests,
  public.user_invitations,
  public.notifications,
  public.ai_requests,
  public.ai_chats,
  public.ai_messages
TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

REVOKE ALL ON public.rate_limits FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.migration_id_mappings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.note_activity_windows FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. RLS Policies
-- -----------------------------------------------------------------------------

-- 3.1 Profiles (self-only direct access; peers fetched via `get_peer_profile` RPC)
DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
CREATE POLICY profiles_select_own ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- 3.2 User Settings (strictly private to owner)
DROP POLICY IF EXISTS user_settings_all_own ON public.user_settings;
CREATE POLICY user_settings_all_own ON public.user_settings
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 3.3 Notes (owner sees active + trashed; live members & pending recipients see active only)
DROP POLICY IF EXISTS notes_select_authorized ON public.notes;
CREATE POLICY notes_select_authorized ON public.notes
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      deleted_at IS NULL
      AND (
        auth.uid() = ANY(live_member_ids)
        OR auth.uid() = ANY(pending_shared_with_user_ids)
      )
    )
  );

DROP POLICY IF EXISTS notes_insert_owner ON public.notes;
CREATE POLICY notes_insert_owner ON public.notes
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND deleted_at IS NULL
    AND revision = 0
    AND cardinality(live_member_ids) = 0
    AND live_roles = '{}'::jsonb
    AND cardinality(shared_with_user_ids) = 0
    AND cardinality(pending_shared_with_user_ids) = 0
  );

DROP POLICY IF EXISTS notes_update_owner_or_editor ON public.notes;
CREATE POLICY notes_update_owner_or_editor ON public.notes
  FOR UPDATE TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      deleted_at IS NULL
      AND auth.uid() = ANY(live_member_ids)
      AND (live_roles ->> (auth.uid()::text)) = 'edit'
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR (
      deleted_at IS NULL
      AND auth.uid() = ANY(live_member_ids)
      AND (live_roles ->> (auth.uid()::text)) = 'edit'
    )
  );

-- Direct client DELETE on `public.notes` is intentionally omitted (denied).
-- Permanent deletion runs via privileged `note-sharing` Edge Function after
-- cleaning up private Storage attachments.

-- 3.4 Personal Favorites (strictly private per user)
DROP POLICY IF EXISTS user_favorites_select_own ON public.user_favorites;
CREATE POLICY user_favorites_select_own ON public.user_favorites
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_favorites_insert_own ON public.user_favorites;
CREATE POLICY user_favorites_insert_own ON public.user_favorites
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.is_note_member(note_id));

DROP POLICY IF EXISTS user_favorites_update_own ON public.user_favorites;
CREATE POLICY user_favorites_update_own ON public.user_favorites
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND public.is_note_member(note_id));

DROP POLICY IF EXISTS user_favorites_delete_own ON public.user_favorites;
CREATE POLICY user_favorites_delete_own ON public.user_favorites
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 3.5 Note Presence (authorized note members only)
DROP POLICY IF EXISTS note_presence_select_member ON public.note_presence;
CREATE POLICY note_presence_select_member ON public.note_presence
  FOR SELECT TO authenticated
  USING (public.is_note_member(note_id));

DROP POLICY IF EXISTS note_presence_insert_self ON public.note_presence;
CREATE POLICY note_presence_insert_self ON public.note_presence
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.is_note_member(note_id));

DROP POLICY IF EXISTS note_presence_update_self ON public.note_presence;
CREATE POLICY note_presence_update_self ON public.note_presence
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND public.is_note_member(note_id))
  WITH CHECK (user_id = auth.uid() AND public.is_note_member(note_id));

DROP POLICY IF EXISTS note_presence_delete_self ON public.note_presence;
CREATE POLICY note_presence_delete_self ON public.note_presence
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 3.6 Connection Requests
DROP POLICY IF EXISTS connections_select_involved ON public.connection_requests;
CREATE POLICY connections_select_involved ON public.connection_requests
  FOR SELECT TO authenticated
  USING (from_user_id = auth.uid() OR to_user_id = auth.uid());

DROP POLICY IF EXISTS connections_update_recipient ON public.connection_requests;
CREATE POLICY connections_update_recipient ON public.connection_requests
  FOR UPDATE TO authenticated
  USING (to_user_id = auth.uid() AND status = 'pending')
  WITH CHECK (to_user_id = auth.uid() AND status IN ('accepted', 'rejected'));

DROP POLICY IF EXISTS connections_delete_involved ON public.connection_requests;
CREATE POLICY connections_delete_involved ON public.connection_requests
  FOR DELETE TO authenticated
  USING (from_user_id = auth.uid() OR to_user_id = auth.uid());

-- 3.7 User Invitations
DROP POLICY IF EXISTS user_invitations_select_own ON public.user_invitations;
CREATE POLICY user_invitations_select_own ON public.user_invitations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_invitations_delete_own ON public.user_invitations;
CREATE POLICY user_invitations_delete_own ON public.user_invitations
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 3.8 Notifications
DROP POLICY IF EXISTS notifications_select_own ON public.notifications;
CREATE POLICY notifications_select_own ON public.notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS notifications_delete_own ON public.notifications;
CREATE POLICY notifications_delete_own ON public.notifications
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 3.9 AI Requests, Chats & Messages
DROP POLICY IF EXISTS ai_requests_select_own ON public.ai_requests;
CREATE POLICY ai_requests_select_own ON public.ai_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS ai_requests_cancel_own ON public.ai_requests;
CREATE POLICY ai_requests_cancel_own ON public.ai_requests
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND cancelled = true AND status = 'cancelled');

DROP POLICY IF EXISTS ai_chats_all_own ON public.ai_chats;
CREATE POLICY ai_chats_all_own ON public.ai_chats
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS ai_messages_select_own ON public.ai_messages;
CREATE POLICY ai_messages_select_own ON public.ai_messages
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS ai_messages_update_feedback ON public.ai_messages;
CREATE POLICY ai_messages_update_feedback ON public.ai_messages
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS ai_messages_delete_own ON public.ai_messages;
CREATE POLICY ai_messages_delete_own ON public.ai_messages
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 4. Column-Guard Triggers (Prevent Privileged Field Tampering via Client PATCH)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_profile_insert_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_email TEXT;
BEGIN
  IF NOT public.is_privileged_context() THEN
    IF NEW.legacy_firebase_uid IS NOT NULL THEN
      RAISE EXCEPTION 'Cannot set protected profile legacy identity column'
        USING ERRCODE = '42501';
    END IF;

    SELECT lower(email) INTO v_auth_email
      FROM auth.users
     WHERE id = auth.uid();

    IF v_auth_email IS NOT NULL AND lower(COALESCE(NEW.email, '')) <> v_auth_email THEN
      RAISE EXCEPTION 'Profile email must match authenticated user email'
        USING ERRCODE = '42501';
    END IF;
    NEW.email := COALESCE(v_auth_email, lower(COALESCE(NEW.email, '')));
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_insert ON public.profiles;
CREATE TRIGGER trg_enforce_profile_insert
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_insert_rules();

CREATE OR REPLACE FUNCTION public.enforce_profile_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.is_privileged_context() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.email IS DISTINCT FROM OLD.email
       OR NEW.legacy_firebase_uid IS DISTINCT FROM OLD.legacy_firebase_uid
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Cannot modify protected profile identity columns'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_update ON public.profiles;
CREATE TRIGGER trg_enforce_profile_update
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_update_rules();

CREATE OR REPLACE FUNCTION public.enforce_note_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.is_privileged_context() THEN
    -- Immutable identity & server-managed sharing columns
    IF NEW.note_id IS DISTINCT FROM OLD.note_id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.source_owner_id IS DISTINCT FROM OLD.source_owner_id
       OR NEW.source_note_id IS DISTINCT FROM OLD.source_note_id
       OR NEW.live_member_ids IS DISTINCT FROM OLD.live_member_ids
       OR NEW.live_roles IS DISTINCT FROM OLD.live_roles
       OR NEW.shared_with_user_ids IS DISTINCT FROM OLD.shared_with_user_ids
       OR NEW.pending_shared_with_user_ids IS DISTINCT FROM OLD.pending_shared_with_user_ids THEN
      RAISE EXCEPTION 'Sharing, membership, and provenance fields are managed server-side'
        USING ERRCODE = '42501';
    END IF;

    -- Non-owner live editor restrictions
    IF OLD.user_id IS DISTINCT FROM auth.uid() THEN
      IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Only the note owner can trash or restore a note'
          USING ERRCODE = '42501';
      END IF;
      IF NEW.is_favorite IS DISTINCT FROM OLD.is_favorite
         OR NEW.owner_name IS DISTINCT FROM OLD.owner_name
         OR NEW.owner_email IS DISTINCT FROM OLD.owner_email THEN
        RAISE EXCEPTION 'Collaborators cannot modify owner metadata or owner favorite flag'
          USING ERRCODE = '42501';
      END IF;
      IF NEW.revision <> OLD.revision + 1 THEN
        RAISE EXCEPTION 'Collaborative updates must increment revision by 1'
          USING ERRCODE = '40001';
      END IF;
      NEW.last_edited_by := auth.uid();
    ELSE
      -- Owner editing content/metadata directly or soft-deleting
      IF NEW.revision < OLD.revision OR NEW.revision > OLD.revision + 1 THEN
        RAISE EXCEPTION 'Invalid note revision step'
          USING ERRCODE = '40001';
      END IF;
    END IF;
    NEW.updated_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_note_update ON public.notes;
CREATE TRIGGER trg_enforce_note_update
  BEFORE UPDATE ON public.notes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_note_update_rules();

CREATE OR REPLACE FUNCTION public.enforce_connection_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.is_privileged_context() THEN
    IF NEW.connection_id IS DISTINCT FROM OLD.connection_id
       OR NEW.from_user_id IS DISTINCT FROM OLD.from_user_id
       OR NEW.from_name IS DISTINCT FROM OLD.from_name
       OR NEW.from_email IS DISTINCT FROM OLD.from_email
       OR NEW.to_user_id IS DISTINCT FROM OLD.to_user_id
       OR NEW.to_name IS DISTINCT FROM OLD.to_name
       OR NEW.to_email IS DISTINCT FROM OLD.to_email
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Cannot alter connection participants'
        USING ERRCODE = '42501';
    END IF;
    IF OLD.status <> 'pending' OR NEW.status NOT IN ('accepted', 'rejected') THEN
      RAISE EXCEPTION 'Only pending requests can be accepted or rejected'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_connection_update ON public.connection_requests;
CREATE TRIGGER trg_enforce_connection_update
  BEFORE UPDATE ON public.connection_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_connection_update_rules();

CREATE OR REPLACE FUNCTION public.enforce_notification_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.is_privileged_context() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.type IS DISTINCT FROM OLD.type
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.body IS DISTINCT FROM OLD.body
       OR NEW.note_id IS DISTINCT FROM OLD.note_id
       OR NEW.actor_id IS DISTINCT FROM OLD.actor_id
       OR NEW.actor_name IS DISTINCT FROM OLD.actor_name
       OR NEW.email_dispatched IS DISTINCT FROM OLD.email_dispatched
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Clients may only mark notifications read/unread'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_notification_update ON public.notifications;
CREATE TRIGGER trg_enforce_notification_update
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_notification_update_rules();

CREATE OR REPLACE FUNCTION public.enforce_ai_request_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.is_privileged_context() THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.request_id IS DISTINCT FROM OLD.request_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
       OR NEW.cancelled IS DISTINCT FROM true
       OR NEW.status IS DISTINCT FROM 'cancelled' THEN
      RAISE EXCEPTION 'Clients may only cancel an in-flight AI request'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_ai_request_update ON public.ai_requests;
CREATE TRIGGER trg_enforce_ai_request_update
  BEFORE UPDATE ON public.ai_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_ai_request_update_rules();

CREATE OR REPLACE FUNCTION public.enforce_ai_message_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.is_privileged_context() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.chat_id IS DISTINCT FROM OLD.chat_id
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.text IS DISTINCT FROM OLD.text
       OR NEW.blocks IS DISTINCT FROM OLD.blocks
       OR NEW.sources IS DISTINCT FROM OLD.sources
       OR NEW.intent IS DISTINCT FROM OLD.intent
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Clients may only update AI message feedback (`fb`)'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_ai_message_update ON public.ai_messages;
CREATE TRIGGER trg_enforce_ai_message_update
  BEFORE UPDATE ON public.ai_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_ai_message_update_rules();

-- -----------------------------------------------------------------------------
-- 5. Activity Notification Triggers (`connectionAccepted` & `liveNoteEdited`)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notify_on_connection_accepted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefs JSONB;
  v_allow BOOLEAN;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
    SELECT preferences INTO v_prefs
      FROM public.user_settings
     WHERE user_id = NEW.from_user_id;

    v_allow := COALESCE((v_prefs ->> 'nRequests')::boolean, true);
    IF v_allow THEN
      INSERT INTO public.notifications (
        user_id, type, title, body, actor_id, actor_name, read, email_dispatched, created_at
      ) VALUES (
        NEW.from_user_id,
        'request',
        'Connection accepted',
        COALESCE(NULLIF(NEW.to_name, ''), NULLIF(NEW.to_email, ''), 'A collaborator') || ' accepted your request.',
        NEW.to_user_id,
        NULLIF(NEW.to_name, ''),
        false,
        false,
        now()
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_connection_accepted ON public.connection_requests;
CREATE TRIGGER trg_notify_connection_accepted
  AFTER UPDATE ON public.connection_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_connection_accepted();

CREATE OR REPLACE FUNCTION public.notify_on_live_note_edited()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor UUID;
  v_actor_name TEXT;
  v_window_key TEXT;
  v_inserted INT;
  v_recipient UUID;
  v_recipients UUID[];
  v_prefs JSONB;
  v_allow BOOLEAN;
BEGIN
  IF NEW.deleted_at IS NOT NULL
     OR NEW.revision <= OLD.revision
     OR cardinality(NEW.live_member_ids) = 0 THEN
    RETURN NEW;
  END IF;

  v_actor := COALESCE(NEW.last_edited_by, auth.uid());
  IF v_actor IS NULL THEN
    RETURN NEW;
  END IF;

  v_window_key := v_actor::text || '_' || floor(extract(epoch FROM now()) / 300)::bigint::text;

  INSERT INTO public.note_activity_windows (note_id, window_key, created_at)
  VALUES (NEW.note_id, v_window_key, now())
  ON CONFLICT (note_id, window_key) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(name, ''), NULLIF(email, ''), 'Collaborator')
    INTO v_actor_name
    FROM public.profiles
   WHERE id = v_actor;
  v_actor_name := COALESCE(v_actor_name, 'Collaborator');

  SELECT array_agg(DISTINCT u)
    INTO v_recipients
    FROM unnest(array_append(NEW.live_member_ids, NEW.user_id)) AS u
   WHERE u IS NOT NULL AND u <> v_actor;

  IF v_recipients IS NULL THEN
    RETURN NEW;
  END IF;

  FOREACH v_recipient IN ARRAY v_recipients LOOP
    SELECT preferences INTO v_prefs
      FROM public.user_settings
     WHERE user_id = v_recipient;

    v_allow := COALESCE((v_prefs ->> 'nLive')::boolean, true);
    IF v_allow THEN
      INSERT INTO public.notifications (
        user_id, type, title, body, note_id, actor_id, actor_name, read, email_dispatched, created_at
      ) VALUES (
        v_recipient,
        'live',
        v_actor_name || ' edited ' || COALESCE(NULLIF(NEW.title, ''), 'Untitled'),
        'Live changes are ready.',
        NEW.note_id,
        v_actor,
        v_actor_name,
        false,
        false,
        now()
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_live_note_edited ON public.notes;
CREATE TRIGGER trg_notify_live_note_edited
  AFTER UPDATE ON public.notes
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_live_note_edited();

-- -----------------------------------------------------------------------------
-- 6. Application & Concurrency RPCs
-- -----------------------------------------------------------------------------

-- 6.1 Safe Peer Profile Lookup (no email enumeration or stranger scraping)
CREATE OR REPLACE FUNCTION public.get_peer_profile(p_target_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.profiles%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  IF NOT public.can_view_peer_profile(p_target_id) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row
    FROM public.profiles
   WHERE id = p_target_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'uid', v_row.id::text,
    'name', v_row.name,
    'fieldOfStudy', v_row.field_of_study,
    'avatarPath', v_row.avatar_path,
    'avatarUrl', v_row.avatar_url,
    'createdAt', v_row.created_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_peer_profile(UUID) TO authenticated;

-- 6.2 Atomic Partial Settings Merge (`merge_user_settings`)
CREATE OR REPLACE FUNCTION public.merge_user_settings(
  p_changes JSONB,
  p_timezone_offset_minutes INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.user_settings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'object' THEN
    RAISE EXCEPTION 'Settings patch must be a JSON object' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.user_settings (
    user_id,
    preferences,
    timezone_offset_minutes,
    notes_schema,
    updated_at
  ) VALUES (
    v_uid,
    p_changes,
    COALESCE(p_timezone_offset_minutes, 0),
    2,
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    preferences = COALESCE(public.user_settings.preferences, '{}'::jsonb) || p_changes,
    timezone_offset_minutes = COALESCE(p_timezone_offset_minutes, public.user_settings.timezone_offset_minutes),
    notes_schema = 2,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row.preferences;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merge_user_settings(JSONB, INT) TO authenticated;

-- 6.3 Decline Pending Note Copy (`decline_note_share`)
CREATE OR REPLACE FUNCTION public.decline_note_share(p_note_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  PERFORM set_config('noted.privileged_op', 'on', true);

  UPDATE public.notes
     SET pending_shared_with_user_ids = array_remove(pending_shared_with_user_ids, v_uid)
   WHERE note_id = p_note_id
     AND v_uid = ANY(pending_shared_with_user_ids);

  PERFORM set_config('noted.privileged_op', 'off', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_note_share(TEXT) TO authenticated;

-- 6.4 Transactional Revision-Checked Collaborative Commit (`commit_note_revision`)
DROP FUNCTION IF EXISTS public.commit_note_revision(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, JSONB);

CREATE OR REPLACE FUNCTION public.commit_note_revision(
  p_note_id TEXT,
  p_expected_revision INT,
  p_title TEXT,
  p_content TEXT,
  p_category TEXT,
  p_color TEXT,
  p_is_favorite BOOLEAN,
  p_attachments JSONB DEFAULT '[]'::jsonb,
  p_created_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_current public.notes%ROWTYPE;
  v_updated public.notes%ROWTYPE;
  v_is_owner BOOLEAN;
  v_is_editor BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_current
    FROM public.notes
   WHERE note_id = p_note_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Note no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  v_is_owner := (v_current.user_id = v_uid);
  v_is_editor := (
    v_current.deleted_at IS NULL
    AND v_uid = ANY(v_current.live_member_ids)
    AND (v_current.live_roles ->> (v_uid::text)) = 'edit'
  );

  IF NOT v_is_owner AND NOT v_is_editor THEN
    RAISE EXCEPTION 'Editing permission denied for this note.' USING ERRCODE = '42501';
  END IF;

  IF v_current.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot edit a note in Recently Deleted.' USING ERRCODE = '42501';
  END IF;

  -- Optimistic concurrency check: if remote advanced, return latest row cleanly
  -- so the client can run Quill Delta Operational Transformation merge!
  IF v_current.revision <> p_expected_revision THEN
    RETURN jsonb_build_object(
      'committed', false,
      'remote', to_jsonb(v_current)
    );
  END IF;

  PERFORM set_config('noted.privileged_op', 'on', true);

  UPDATE public.notes
     SET title = COALESCE(p_title, ''),
         content = COALESCE(p_content, ''),
         category = COALESCE(p_category, 'Personal'),
         color = COALESCE(p_color, v_current.color),
         is_favorite = CASE WHEN v_is_owner THEN COALESCE(p_is_favorite, v_current.is_favorite) ELSE v_current.is_favorite END,
         attachments = COALESCE(p_attachments, '[]'::jsonb),
         created_at = COALESCE(p_created_at, v_current.created_at),
         revision = v_current.revision + 1,
         last_edited_by = v_uid,
         updated_at = now()
   WHERE note_id = p_note_id
  RETURNING * INTO v_updated;

  PERFORM set_config('noted.privileged_op', 'off', true);

  RETURN jsonb_build_object(
    'committed', true,
    'note', to_jsonb(v_updated)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.commit_note_revision(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, JSONB, TIMESTAMPTZ)
  TO authenticated;

-- 6.5 Server-Side Rate Limit Counter (`check_rate_limit`)
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_user_id UUID,
  p_operation TEXT,
  p_limit INT,
  p_window_seconds INT DEFAULT 3600
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.rate_limits%ROWTYPE;
  v_now TIMESTAMPTZ := now();
BEGIN
  IF NOT public.is_privileged_context() THEN
    RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
    FROM public.rate_limits
   WHERE user_id = p_user_id AND operation = p_operation
   FOR UPDATE;

  IF NOT FOUND OR v_row.reset_at <= v_now THEN
    INSERT INTO public.rate_limits (user_id, operation, count, reset_at)
    VALUES (p_user_id, p_operation, 1, v_now + make_interval(secs => p_window_seconds))
    ON CONFLICT (user_id, operation) DO UPDATE SET
      count = 1,
      reset_at = v_now + make_interval(secs => p_window_seconds);
    RETURN true;
  END IF;

  IF v_row.count >= p_limit THEN
    RETURN false;
  END IF;

  UPDATE public.rate_limits
     SET count = v_row.count + 1
   WHERE user_id = p_user_id AND operation = p_operation;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.check_rate_limit(UUID, TEXT, INT, INT) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 7. Supabase Realtime Publication Registration
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_table TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH v_table IN ARRAY ARRAY[
      'profiles',
      'user_settings',
      'notes',
      'user_favorites',
      'note_presence',
      'connection_requests',
      'user_invitations',
      'notifications',
      'ai_requests',
      'ai_chats',
      'ai_messages'
    ] LOOP
      IF NOT EXISTS (
        SELECT 1
          FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime'
           AND schemaname = 'public'
           AND tablename = v_table
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
      END IF;
    END LOOP;
  END IF;
END;
$$;
