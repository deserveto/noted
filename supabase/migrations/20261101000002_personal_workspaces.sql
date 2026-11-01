CREATE TABLE public.personal_workspaces (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 100),
 UNIQUE (user_id, id)
);
CREATE TABLE public.personal_workspace_notes (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 note_id text NOT NULL REFERENCES public.notes(note_id) ON DELETE CASCADE,
 workspace_id uuid NOT NULL,
 PRIMARY KEY (user_id, note_id),
 FOREIGN KEY (user_id, workspace_id) REFERENCES public.personal_workspaces(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.personal_workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal_workspace_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_workspaces_own ON public.personal_workspaces FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY personal_workspace_notes_own ON public.personal_workspace_notes FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid() AND public.is_note_member(note_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.personal_workspaces, public.personal_workspace_notes TO authenticated;
CREATE TRIGGER audit_guard_account_writes BEFORE INSERT OR UPDATE ON public.personal_workspaces FOR EACH ROW EXECUTE FUNCTION public.audit_guard_account_writes();
CREATE TRIGGER audit_guard_account_writes BEFORE INSERT OR UPDATE ON public.personal_workspace_notes FOR EACH ROW EXECUTE FUNCTION public.audit_guard_account_writes();

-- Refuse rollback if personal workspace assignments depend on imported notes.
CREATE OR REPLACE FUNCTION public.audit_rollback_migration(p_dry_run boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE saved public.audit_migration_rollback_seal%ROWTYPE; counts jsonb; retained jsonb;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_dry_run IS NULL THEN RAISE EXCEPTION 'dry run required' USING ERRCODE='22023'; END IF;
 LOCK TABLE auth.users, storage.objects, public.migration_id_mappings, public.audit_migration_rollback_seal, public.profiles, public.user_settings, public.notes, public.user_favorites, public.note_presence, public.note_activity_windows, public.connection_requests, public.user_invitations, public.notifications, public.ai_requests, public.ai_chats, public.ai_messages, public.rate_limits, public.note_deletion_tombstones, public.deleting_accounts, public.audit_copy_cleanup_reservations, public.audit_copy_sweeps, public.audit_email_cursor, public.personal_workspace_notes IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO saved FROM public.audit_migration_rollback_seal WHERE id=true;
 IF NOT FOUND OR saved.snapshot='{}'::jsonb OR saved.rolled_back_at IS NOT NULL THEN RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('No active trusted rollback seal')); END IF;
 IF saved.snapshot IS DISTINCT FROM public.audit_migration_state() THEN RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('Database changed since the rollback seal')); END IF;
 -- Reject new foreign-key relationships unless explicitly examined below.
 IF EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_class child ON child.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=child.relnamespace
   WHERE c.contype='f' AND c.confrelid IN ('public.notes'::regclass,'public.ai_chats'::regclass)
     AND NOT (ns.nspname='public' AND child.relname = ANY(ARRAY['user_favorites','note_presence','note_activity_windows','ai_messages','personal_workspace_notes']))) THEN
   RETURN jsonb_build_object('dryRun',p_dry_run,'errors',jsonb_build_array('Unknown cascade dependency'));
 END IF;
 IF EXISTS(SELECT 1 FROM public.personal_workspace_notes x JOIN public.migration_id_mappings m ON m.entity_type='note' AND m.supabase_id=x.note_id)
 OR EXISTS(SELECT 1 FROM public.note_presence x JOIN public.migration_id_mappings m ON m.entity_type='note' AND m.supabase_id=x.note_id)
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
