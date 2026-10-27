-- Forward-only audit fixes.

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
  v_legacy_uid := NULL;

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
         WHERE c.status IN ('pending', 'accepted') AND ((c.from_user_id = auth.uid() AND c.to_user_id = p_target_id)
            OR (c.to_user_id = auth.uid() AND c.from_user_id = p_target_id))
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

    v_allow := CASE WHEN jsonb_typeof(v_prefs -> 'nRequests') = 'boolean' THEN (v_prefs ->> 'nRequests')::boolean ELSE true END;
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
  v_actor_name := left(COALESCE(v_actor_name, 'Collaborator'), 200);

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

    v_allow := CASE WHEN jsonb_typeof(v_prefs -> 'nLive') = 'boolean' THEN (v_prefs ->> 'nLive')::boolean ELSE true END;
    IF v_allow THEN
      INSERT INTO public.notifications (
        user_id, type, title, body, note_id, actor_id, actor_name, read, email_dispatched, created_at
      ) VALUES (
        v_recipient,
        'live',
        left(v_actor_name || ' edited ' || COALESCE(NULLIF(NEW.title, ''), 'Untitled'), 300),
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
         is_favorite = v_current.is_favorite,
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
      -- Every direct content mutation advances the shared revision.
      IF (NEW.title, NEW.content, NEW.category, NEW.color, NEW.attachments) IS DISTINCT FROM (OLD.title, OLD.content, OLD.category, OLD.color, OLD.attachments) AND NEW.revision = OLD.revision THEN
        NEW.revision := OLD.revision + 1;
      END IF;
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

-- Validate known keys without discarding previously stored or future keys.
CREATE OR REPLACE FUNCTION public.audit_validate_preferences() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE k text; expected text;
BEGIN
  FOR k, expected IN SELECT key, value FROM jsonb_each_text(jsonb_build_object(
    'theme','string','textSize','number','density','string','reduceMotion','boolean',
    'defaultCat','string','defaultColor','string','spellcheck','boolean','wordCount','boolean',
    'defaultView','string','defaultSort','string','weekStart','string','calendarDots','boolean',
    'aiEnabled','boolean','aiSources','boolean','aiLength','string','aiTone','string','aiHistory','boolean',
    'requests','string','livePerm','string','presence','boolean','reshare','boolean','copies','boolean',
    'nLive','boolean','nRequests','boolean','nCopies','boolean','nRecap','boolean','quietHours','boolean',
    'appLock','boolean','analytics','boolean')) LOOP
    IF NEW.preferences ? k AND jsonb_typeof(NEW.preferences -> k) <> expected
       AND (TG_OP = 'INSERT' OR NEW.preferences -> k IS DISTINCT FROM OLD.preferences -> k) THEN
      RAISE EXCEPTION 'Invalid type for preference %', k USING ERRCODE = '22023';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS audit_validate_preferences ON public.user_settings;
CREATE TRIGGER audit_validate_preferences BEFORE INSERT OR UPDATE ON public.user_settings
FOR EACH ROW EXECUTE FUNCTION public.audit_validate_preferences();

CREATE OR REPLACE FUNCTION public.check_rate_limit(p_user_id uuid,p_operation text,p_limit int,p_window_seconds int DEFAULT 3600)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_limit <= 0 OR p_window_seconds <= 0 THEN RAISE EXCEPTION 'Invalid limit' USING ERRCODE='22023'; END IF;
 INSERT INTO public.rate_limits AS r(user_id,operation,count,reset_at)
 VALUES(p_user_id,p_operation,1,clock_timestamp()+make_interval(secs=>p_window_seconds))
 ON CONFLICT(user_id,operation) DO UPDATE SET
 count = CASE WHEN r.reset_at <= clock_timestamp() THEN 1 ELSE r.count+1 END,
 reset_at = CASE WHEN r.reset_at <= clock_timestamp() THEN clock_timestamp()+make_interval(secs=>p_window_seconds) ELSE r.reset_at END
 WHERE r.reset_at <= clock_timestamp() OR r.count < p_limit
 RETURNING count INTO v_count;
 RETURN v_count IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.check_rate_limit(uuid,text,int,int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,int,int) TO service_role;

-- All sharing mutations lock the authoritative note before checking permissions.
CREATE OR REPLACE FUNCTION public.audit_set_live_role(p_note_id text,p_actor_id uuid,p_target_id uuid,p_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n public.notes%ROWTYPE; changed boolean;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_actor_id::text,0));
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_target_id::text,0));
 PERFORM public.audit_assert_account_active(p_actor_id);
 PERFORM public.audit_assert_account_active(p_target_id);
 IF p_actor_id IS NULL OR p_target_id IS NULL OR p_actor_id=p_target_id OR p_role NOT IN ('edit','view','none') OR p_role IS NULL THEN RAISE EXCEPTION 'Invalid sharing request' USING ERRCODE='22023'; END IF;
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR UPDATE;
 IF NOT FOUND OR n.user_id<>p_actor_id OR n.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Only the owner can share' USING ERRCODE='42501'; END IF;
 IF p_role <> 'none' THEN
   IF n.source_owner_id IS NOT NULL AND n.source_owner_id<>p_actor_id AND EXISTS(SELECT 1 FROM public.user_settings WHERE user_id=n.source_owner_id AND preferences->'reshare' = 'false'::jsonb) THEN RAISE EXCEPTION 'Resharing disabled' USING ERRCODE='42501'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.connection_requests WHERE status='accepted' AND ((from_user_id=p_actor_id AND to_user_id=p_target_id) OR (to_user_id=p_actor_id AND from_user_id=p_target_id))) THEN RAISE EXCEPTION 'Connection required' USING ERRCODE='42501'; END IF;
 END IF;
 changed := CASE WHEN p_role='none' THEN p_target_id=ANY(n.live_member_ids) OR n.live_roles ? p_target_id::text ELSE NOT (p_target_id=ANY(n.live_member_ids)) OR n.live_roles->>p_target_id::text IS DISTINCT FROM p_role END;
 IF changed THEN
 UPDATE public.notes SET live_member_ids=CASE WHEN p_role='none' THEN array_remove(live_member_ids,p_target_id) ELSE array_append(array_remove(live_member_ids,p_target_id),p_target_id) END,
 live_roles=CASE WHEN p_role='none' THEN live_roles-p_target_id::text ELSE jsonb_set(live_roles,ARRAY[p_target_id::text],to_jsonb(p_role),true) END WHERE note_id=p_note_id RETURNING * INTO n;
 IF p_role='none' THEN DELETE FROM public.note_presence WHERE note_id=p_note_id AND user_id=p_target_id; END IF;
 END IF;
 RETURN jsonb_build_object('changed',changed,'note',to_jsonb(n));
END $$;

CREATE OR REPLACE FUNCTION public.audit_queue_note_copy(p_note_id text,p_actor_id uuid,p_target_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n public.notes%ROWTYPE; changed boolean;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_actor_id::text,0));
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_target_id::text,0));
 PERFORM public.audit_assert_account_active(p_actor_id);
 PERFORM public.audit_assert_account_active(p_target_id);
 IF p_actor_id IS NULL OR p_target_id IS NULL OR p_actor_id=p_target_id THEN RAISE EXCEPTION 'Invalid request' USING ERRCODE='22023'; END IF;
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR UPDATE;
 IF NOT FOUND OR n.user_id<>p_actor_id OR n.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Only owner can share' USING ERRCODE='42501'; END IF;
 IF n.source_owner_id IS NOT NULL AND n.source_owner_id<>p_actor_id AND EXISTS(SELECT 1 FROM public.user_settings WHERE user_id=n.source_owner_id AND preferences->'reshare'='false'::jsonb) THEN RAISE EXCEPTION 'Resharing disabled' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.connection_requests WHERE status='accepted' AND ((from_user_id=p_actor_id AND to_user_id=p_target_id) OR (to_user_id=p_actor_id AND from_user_id=p_target_id))) THEN RAISE EXCEPTION 'Connection required' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.user_settings WHERE user_id=p_target_id AND preferences->'copies'='false'::jsonb) THEN RAISE EXCEPTION 'Copies disabled' USING ERRCODE='42501'; END IF;
 changed := NOT p_target_id=ANY(n.pending_shared_with_user_ids);
 IF changed THEN UPDATE public.notes SET pending_shared_with_user_ids=array_append(array_remove(pending_shared_with_user_ids,p_target_id),p_target_id), shared_with_user_ids=array_append(array_remove(shared_with_user_ids,p_target_id),p_target_id) WHERE note_id=p_note_id RETURNING * INTO n; END IF;
 RETURN jsonb_build_object('changed',changed,'note',to_jsonb(n));
END $$;

CREATE OR REPLACE FUNCTION public.audit_accept_note_copy(p_note_id text,p_actor_id uuid,p_expected_revision int,p_copy jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n public.notes%ROWTYPE; copied public.notes%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_actor_id::text,0));
 PERFORM public.audit_assert_account_active(p_actor_id);
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR UPDATE;
 IF NOT FOUND OR n.deleted_at IS NOT NULL OR p_actor_id IS NULL OR NOT p_actor_id=ANY(n.pending_shared_with_user_ids) THEN RAISE EXCEPTION 'No pending copy' USING ERRCODE='42501'; END IF;
 IF n.revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'Source changed; retry copy' USING ERRCODE='40001'; END IF;
 INSERT INTO public.notes(note_id,user_id,owner_name,owner_email,title,content,category,color,is_favorite,source_owner_id,source_note_id,attachments,last_edited_by)
 VALUES(p_copy->>'note_id',p_actor_id,COALESCE(p_copy->>'owner_name',''),COALESCE(p_copy->>'owner_email',''),n.title,COALESCE(p_copy->>'content',''),n.category,n.color,false,COALESCE(n.source_owner_id,n.user_id),COALESCE(n.source_note_id,n.note_id),COALESCE(p_copy->'attachments','[]'::jsonb),p_actor_id) RETURNING * INTO copied;
 UPDATE public.notes SET pending_shared_with_user_ids=array_remove(pending_shared_with_user_ids,p_actor_id) WHERE note_id=p_note_id;
 RETURN jsonb_build_object('note',to_jsonb(copied));
END $$;

CREATE OR REPLACE FUNCTION public.audit_remove_user_memberships(p_user_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE affected integer;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'Invalid user' USING ERRCODE='22023'; END IF;
 UPDATE public.notes SET live_member_ids=array_remove(live_member_ids,p_user_id),live_roles=live_roles-p_user_id::text,shared_with_user_ids=array_remove(shared_with_user_ids,p_user_id),pending_shared_with_user_ids=array_remove(pending_shared_with_user_ids,p_user_id)
 WHERE p_user_id=ANY(live_member_ids) OR live_roles ? p_user_id::text OR p_user_id=ANY(shared_with_user_ids) OR p_user_id=ANY(pending_shared_with_user_ids);
 GET DIAGNOSTICS affected = ROW_COUNT;
 DELETE FROM public.note_presence WHERE user_id=p_user_id;
 RETURN affected;
END $$;
REVOKE ALL ON FUNCTION public.audit_set_live_role(text,uuid,uuid,text),public.audit_queue_note_copy(text,uuid,uuid),public.audit_accept_note_copy(text,uuid,int,jsonb),public.audit_remove_user_memberships(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_set_live_role(text,uuid,uuid,text),public.audit_queue_note_copy(text,uuid,uuid),public.audit_accept_note_copy(text,uuid,int,jsonb),public.audit_remove_user_memberships(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.commit_note_revision(text,int,text,text,text,text,boolean,jsonb,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.commit_note_revision(text,int,text,text,text,text,boolean,jsonb,timestamptz) TO authenticated;
