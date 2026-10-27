-- A durable deletion barrier is installed before any account media enumeration.
CREATE TABLE public.deleting_accounts(user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, started_at timestamptz NOT NULL DEFAULT now());
REVOKE ALL ON public.deleting_accounts FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.audit_account_active(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_catalog AS $$
 SELECT p_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.deleting_accounts WHERE user_id=p_user_id)
$$;
CREATE OR REPLACE FUNCTION public.audit_assert_account_active(p_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.audit_account_active(p_user_id) THEN RAISE EXCEPTION 'Account deletion in progress' USING ERRCODE='55000'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.audit_assert_account_active(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.audit_guard_account_writes() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE row_data jsonb:=to_jsonb(NEW); old_data jsonb; subject uuid; id_text text;
BEGIN
 IF auth.uid() IS NOT NULL THEN PERFORM public.audit_assert_account_active(auth.uid()); END IF;
 IF TG_TABLE_NAME='profiles' THEN id_text:=row_data->>'id'; ELSE id_text:=row_data->>'user_id'; END IF;
 IF id_text IS NOT NULL THEN PERFORM public.audit_assert_account_active(id_text::uuid); END IF;
 IF TG_TABLE_NAME='connection_requests' THEN
   PERFORM public.audit_assert_account_active((row_data->>'from_user_id')::uuid);
   PERFORM public.audit_assert_account_active((row_data->>'to_user_id')::uuid);
 END IF;
 IF TG_TABLE_NAME='notes' THEN
   old_data := CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END;
   FOR subject IN SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(row_data->'live_member_ids','[]'::jsonb) || COALESCE(row_data->'pending_shared_with_user_ids','[]'::jsonb) || COALESCE(row_data->'shared_with_user_ids','[]'::jsonb))
   LOOP
     IF NOT (COALESCE(old_data->'live_member_ids','[]'::jsonb) ? subject::text OR COALESCE(old_data->'pending_shared_with_user_ids','[]'::jsonb) ? subject::text OR COALESCE(old_data->'shared_with_user_ids','[]'::jsonb) ? subject::text) THEN
       PERFORM public.audit_assert_account_active(subject);
     END IF;
   END LOOP;
 END IF;
 RETURN NEW;
END $$;
DO $$
DECLARE tbl text;
BEGIN
 FOREACH tbl IN ARRAY ARRAY['profiles','user_settings','notes','user_favorites','note_presence','connection_requests','user_invitations','notifications','ai_requests','ai_chats','ai_messages','rate_limits'] LOOP
   EXECUTE format('CREATE TRIGGER audit_guard_account_writes BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_guard_account_writes()',tbl);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.audit_begin_account_deletion(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE pending integer;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'Invalid user' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('noted-account:' || p_user_id::text,0));
 LOCK TABLE auth.users, storage.objects, public.profiles, public.user_settings, public.notes, public.user_favorites, public.note_presence, public.connection_requests, public.user_invitations, public.notifications, public.ai_requests, public.ai_chats, public.ai_messages, public.rate_limits IN SHARE ROW EXCLUSIVE MODE;
 INSERT INTO public.deleting_accounts(user_id) VALUES(p_user_id) ON CONFLICT DO NOTHING;
 SELECT count(*) INTO pending FROM public.audit_copy_cleanup_reservations WHERE user_id=p_user_id;
 RETURN jsonb_build_object('started',true,'pendingCopies',pending);
END $$;
REVOKE ALL ON FUNCTION public.audit_begin_account_deletion(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_begin_account_deletion(uuid) TO service_role;

-- Storage writes lock the note and reject deleting owners and uploaders.
CREATE OR REPLACE FUNCTION public.is_note_editor(p_note_id text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE n public.notes%ROWTYPE;
BEGIN
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR SHARE;
 RETURN FOUND AND n.deleted_at IS NULL AND n.deletion_started_at IS NULL
   AND public.audit_account_active(n.user_id) AND public.audit_account_active(auth.uid())
   AND (n.user_id=auth.uid() OR (auth.uid()=ANY(n.live_member_ids) AND n.live_roles->>auth.uid()::text='edit'));
END $$;
REVOKE ALL ON FUNCTION public.audit_account_active(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.audit_account_active(uuid) TO authenticated,service_role;

-- Restrictive policies apply in addition to the existing bucket/path policies.
CREATE POLICY audit_storage_insert_active ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK (public.audit_account_active(auth.uid()) AND (bucket_id <> 'note-media' OR public.is_note_editor(public.storage_path_segment(name,4))));
CREATE POLICY audit_storage_update_active ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
 USING (public.audit_account_active(auth.uid()) AND (bucket_id <> 'note-media' OR public.is_note_editor(public.storage_path_segment(name,4))))
 WITH CHECK (public.audit_account_active(auth.uid()) AND (bucket_id <> 'note-media' OR public.is_note_editor(public.storage_path_segment(name,4))));
