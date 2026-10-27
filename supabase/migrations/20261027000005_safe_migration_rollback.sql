-- Conservative, opt-in rollback for a fresh, offline import. Storage and
-- Auth identities are deliberately retained because they are external to this transaction.
CREATE TABLE IF NOT EXISTS public.audit_migration_rollback_seal (
 id boolean PRIMARY KEY DEFAULT true CHECK (id),
 snapshot jsonb NOT NULL,
 sealed_at timestamptz NOT NULL DEFAULT now(),
 rolled_back_at timestamptz
);
REVOKE ALL ON public.audit_migration_rollback_seal FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.audit_migration_state() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE table_name text; rows_json jsonb; result jsonb := '{}'::jsonb;
BEGIN
 FOREACH table_name IN ARRAY ARRAY['migration_id_mappings','profiles','user_settings','notes','user_favorites','note_presence','note_activity_windows','connection_requests','user_invitations','notifications','ai_requests','ai_chats','ai_messages','rate_limits','note_deletion_tombstones','deleting_accounts','audit_copy_cleanup_reservations','audit_copy_sweeps','audit_email_cursor'] LOOP
   EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) FROM public.%I t',table_name) INTO rows_json;
   result := result || jsonb_build_object(table_name,rows_json);
 END LOOP;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',u.id) ORDER BY u.id::text),'[]'::jsonb) INTO rows_json FROM auth.users u;
 result:=result || jsonb_build_object('auth_users',rows_json);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('bucket_id',o.bucket_id,'name',o.name) ORDER BY o.bucket_id,o.name),'[]'::jsonb) INTO rows_json FROM storage.objects o;
 result:=result || jsonb_build_object('storage_objects',rows_json);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.audit_migration_state() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.audit_seal_migration_rollback(p_expected_state jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 LOCK TABLE auth.users, storage.objects, public.migration_id_mappings, public.audit_migration_rollback_seal, public.profiles, public.user_settings, public.notes, public.user_favorites, public.note_presence, public.note_activity_windows, public.connection_requests, public.user_invitations, public.notifications, public.ai_requests, public.ai_chats, public.ai_messages, public.rate_limits, public.note_deletion_tombstones, public.deleting_accounts, public.audit_copy_cleanup_reservations, public.audit_copy_sweeps, public.audit_email_cursor IN SHARE ROW EXCLUSIVE MODE;
 IF NOT EXISTS(SELECT 1 FROM public.audit_migration_rollback_seal WHERE id=true AND snapshot='{}'::jsonb AND rolled_back_at IS NULL) THEN RAISE EXCEPTION 'Fresh-target preflight missing or rollback seal already exists' USING ERRCODE='55000'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.migration_id_mappings) THEN RAISE EXCEPTION 'No imported mappings to seal' USING ERRCODE='55000'; END IF;
 IF p_expected_state IS NULL OR p_expected_state IS DISTINCT FROM public.audit_migration_state() THEN RAISE EXCEPTION 'Target does not match validated snapshot' USING ERRCODE='55000'; END IF;
 UPDATE public.audit_migration_rollback_seal SET snapshot=p_expected_state,sealed_at=now() WHERE id=true;
 RETURN jsonb_build_object('sealed',true);
END $$;

CREATE OR REPLACE FUNCTION public.audit_rollback_migration(p_dry_run boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE saved public.audit_migration_rollback_seal%ROWTYPE; counts jsonb; retained jsonb;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_dry_run IS NULL THEN RAISE EXCEPTION 'dry run required' USING ERRCODE='22023'; END IF;
 LOCK TABLE auth.users, storage.objects, public.migration_id_mappings, public.audit_migration_rollback_seal, public.profiles, public.user_settings, public.notes, public.user_favorites, public.note_presence, public.note_activity_windows, public.connection_requests, public.user_invitations, public.notifications, public.ai_requests, public.ai_chats, public.ai_messages, public.rate_limits, public.note_deletion_tombstones, public.deleting_accounts, public.audit_copy_cleanup_reservations, public.audit_copy_sweeps, public.audit_email_cursor IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO saved FROM public.audit_migration_rollback_seal WHERE id=true;
 IF NOT FOUND OR saved.snapshot='{}'::jsonb OR saved.rolled_back_at IS NOT NULL THEN RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('No active trusted rollback seal')); END IF;
 IF saved.snapshot IS DISTINCT FROM public.audit_migration_state() THEN RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('Database changed since the rollback seal')); END IF;
 -- Reject new foreign-key relationships unless explicitly examined below.
 IF EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_class child ON child.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=child.relnamespace
   WHERE c.contype='f' AND c.confrelid IN ('public.notes'::regclass,'public.ai_chats'::regclass)
     AND NOT (ns.nspname='public' AND child.relname = ANY(ARRAY['user_favorites','note_presence','note_activity_windows','ai_messages']))) THEN
   RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('Unknown cascade dependency'));
 END IF;
 IF EXISTS(SELECT 1 FROM public.note_presence x JOIN public.migration_id_mappings m ON m.entity_type='note' AND m.supabase_id=x.note_id)
 OR EXISTS(SELECT 1 FROM public.note_activity_windows x JOIN public.migration_id_mappings m ON m.entity_type='note' AND m.supabase_id=x.note_id)
 OR EXISTS(SELECT 1 FROM public.user_favorites x JOIN public.migration_id_mappings m ON m.entity_type='note' AND m.supabase_id=x.note_id WHERE NOT EXISTS(SELECT 1 FROM public.migration_id_mappings f WHERE f.entity_type='favorite' AND f.supabase_id=x.user_id::text || '_' || x.note_id))
 OR EXISTS(SELECT 1 FROM public.ai_messages x JOIN public.migration_id_mappings m ON m.entity_type='chat' AND m.supabase_id=x.user_id::text || '_' || x.chat_id WHERE NOT EXISTS(SELECT 1 FROM public.migration_id_mappings f WHERE f.entity_type='message' AND f.supabase_id=x.id)) THEN
   RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('Unmapped dependent rows would be affected'));
 END IF;
 SELECT jsonb_build_object('notes',count(*) FILTER(WHERE entity_type='note'), 'favorites',count(*) FILTER(WHERE entity_type='favorite'), 'connections',count(*) FILTER(WHERE entity_type='connection'), 'invitations',count(*) FILTER(WHERE entity_type='invitation'), 'notifications',count(*) FILTER(WHERE entity_type='notification'), 'chats',count(*) FILTER(WHERE entity_type='chat'), 'messages',count(*) FILTER(WHERE entity_type='message'), 'aiRequests',count(*) FILTER(WHERE entity_type='ai_request')),
 jsonb_build_object('authUsers',count(*) FILTER(WHERE entity_type='user'),'profiles',count(*) FILTER(WHERE entity_type='user'),'settings',count(*) FILTER(WHERE entity_type='setting'),'media',count(*) FILTER(WHERE entity_type='media')) INTO counts,retained FROM public.migration_id_mappings;
 IF NOT p_dry_run THEN
 DELETE FROM public.ai_messages x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='message' AND m.supabase_id=x.id);
 DELETE FROM public.ai_chats x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='chat' AND m.supabase_id=x.user_id::text || '_' || x.chat_id);
 DELETE FROM public.ai_requests x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='ai_request' AND m.supabase_id=x.user_id::text || '_' || x.request_id);
 DELETE FROM public.notifications x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='notification' AND m.supabase_id=x.id);
 DELETE FROM public.user_invitations x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='invitation' AND m.supabase_id=x.user_id::text || '_' || x.email_hash);
 DELETE FROM public.user_favorites x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='favorite' AND m.supabase_id=x.user_id::text || '_' || x.note_id);
 DELETE FROM public.connection_requests x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='connection' AND m.supabase_id=x.connection_id);
 DELETE FROM public.notes x WHERE EXISTS(SELECT 1 FROM public.migration_id_mappings m WHERE m.entity_type='note' AND m.supabase_id=x.note_id);
 DELETE FROM public.migration_id_mappings WHERE entity_type IN ('message','chat','ai_request','notification','invitation','favorite','connection','note');
 UPDATE public.audit_migration_rollback_seal SET rolled_back_at=now() WHERE id=true;
 END IF;
 RETURN jsonb_build_object('dryRun',p_dry_run,'deletedCounts',counts,'retained',retained,'errors','[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.audit_seal_migration_rollback(jsonb),public.audit_rollback_migration(boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_seal_migration_rollback(jsonb),public.audit_rollback_migration(boolean) TO service_role;

-- This preflight is meaningful only while operators keep the target offline
-- throughout the subsequent multi-request import and sealing operation.
CREATE OR REPLACE FUNCTION public.audit_assert_migration_target_empty() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE name text; found_row boolean;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 LOCK TABLE auth.users, storage.objects, public.migration_id_mappings, public.audit_migration_rollback_seal, public.profiles, public.user_settings, public.notes, public.user_favorites, public.note_presence, public.note_activity_windows, public.connection_requests, public.user_invitations, public.notifications, public.ai_requests, public.ai_chats, public.ai_messages, public.rate_limits, public.note_deletion_tombstones, public.deleting_accounts, public.audit_copy_cleanup_reservations, public.audit_copy_sweeps, public.audit_email_cursor IN SHARE ROW EXCLUSIVE MODE;
 IF EXISTS(SELECT 1 FROM auth.users) OR EXISTS(SELECT 1 FROM storage.objects) OR EXISTS(SELECT 1 FROM public.audit_migration_rollback_seal) THEN RAISE EXCEPTION 'Target is not empty' USING ERRCODE='55000'; END IF;
 FOR name IN SELECT jsonb_object_keys(public.audit_migration_state()) EXCEPT SELECT unnest(ARRAY['auth_users','storage_objects']) LOOP
   EXECUTE format('SELECT EXISTS(SELECT 1 FROM public.%I)',name) INTO found_row;
   IF found_row THEN RAISE EXCEPTION 'Target is not empty: %',name USING ERRCODE='55000'; END IF;
 END LOOP;
 INSERT INTO public.audit_migration_rollback_seal(id,snapshot) VALUES(true,'{}'::jsonb);
 RETURN jsonb_build_object('empty',true);
END $$;
REVOKE ALL ON FUNCTION public.audit_assert_migration_target_empty() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_assert_migration_target_empty() TO service_role;
-- Capture a consistent database snapshot for source-parity validation before seal.
CREATE OR REPLACE FUNCTION public.audit_get_migration_rollback_state() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 LOCK TABLE auth.users, storage.objects, public.migration_id_mappings, public.audit_migration_rollback_seal, public.profiles, public.user_settings, public.notes, public.user_favorites, public.note_presence, public.note_activity_windows, public.connection_requests, public.user_invitations, public.notifications, public.ai_requests, public.ai_chats, public.ai_messages, public.rate_limits, public.note_deletion_tombstones, public.deleting_accounts, public.audit_copy_cleanup_reservations, public.audit_copy_sweeps, public.audit_email_cursor IN SHARE ROW EXCLUSIVE MODE;
 IF NOT EXISTS(SELECT 1 FROM public.audit_migration_rollback_seal WHERE id=true AND snapshot='{}'::jsonb AND rolled_back_at IS NULL) THEN RAISE EXCEPTION 'Fresh-target preflight missing or already sealed' USING ERRCODE='55000'; END IF;
 RETURN public.audit_migration_state();
END $$;
REVOKE ALL ON FUNCTION public.audit_get_migration_rollback_state() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_get_migration_rollback_state() TO service_role;
