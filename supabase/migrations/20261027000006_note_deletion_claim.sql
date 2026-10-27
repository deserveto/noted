-- A durable tombstone reserves an ID while remote media cleanup is pending and
-- after completion, so another request cannot recreate a note under that path.
ALTER TABLE public.notes ADD COLUMN IF NOT EXISTS deletion_started_at timestamptz;
ALTER TABLE public.ai_messages ADD COLUMN IF NOT EXISTS context_dependencies jsonb
  CHECK (context_dependencies IS NULL OR jsonb_typeof(context_dependencies)='array');
CREATE TABLE IF NOT EXISTS public.note_deletion_tombstones (
  note_id text PRIMARY KEY,
  owner_id uuid NOT NULL,
  claimed_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON public.note_deletion_tombstones FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.audit_guard_note_deletion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF TG_OP='INSERT' THEN
   IF NEW.deletion_started_at IS NOT NULL OR EXISTS(SELECT 1 FROM public.note_deletion_tombstones WHERE note_id=NEW.note_id) THEN
     RAISE EXCEPTION 'Note ID reserved for deletion' USING ERRCODE='42501';
   END IF;
 ELSIF OLD.deletion_started_at IS NOT NULL THEN
   RAISE EXCEPTION 'Note deletion is in progress' USING ERRCODE='55000';
 ELSIF NEW.deletion_started_at IS DISTINCT FROM OLD.deletion_started_at AND NOT public.is_privileged_context() THEN
   RAISE EXCEPTION 'Deletion claim is server-managed' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS audit_guard_note_deletion ON public.notes;
CREATE TRIGGER audit_guard_note_deletion BEFORE INSERT OR UPDATE ON public.notes FOR EACH ROW EXECUTE FUNCTION public.audit_guard_note_deletion();

-- Serialize client uploads with the deletion claim and deny uploads once trashed.
CREATE OR REPLACE FUNCTION public.is_note_editor(p_note_id text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE n public.notes%ROWTYPE;
BEGIN
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR SHARE;
 RETURN FOUND AND n.deleted_at IS NULL AND n.deletion_started_at IS NULL AND
   (n.user_id=auth.uid() OR (auth.uid()=ANY(n.live_member_ids) AND n.live_roles->>auth.uid()::text='edit'));
END $$;

CREATE OR REPLACE FUNCTION public.audit_claim_note_deletion(p_note_id text,p_owner_id uuid,p_before timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE n public.notes%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR UPDATE;
 IF NOT FOUND OR p_owner_id IS NULL OR n.user_id<>p_owner_id OR n.deleted_at IS NULL OR (p_before IS NOT NULL AND n.deleted_at>p_before) THEN
   RETURN jsonb_build_object('claimed',false,'note',NULL);
 END IF;
 IF n.deletion_started_at IS NULL THEN
   INSERT INTO public.note_deletion_tombstones(note_id,owner_id) VALUES(n.note_id,n.user_id) ON CONFLICT(note_id) DO NOTHING;
   UPDATE public.notes SET deletion_started_at=now() WHERE note_id=p_note_id RETURNING * INTO n;
 END IF;
 RETURN jsonb_build_object('claimed',true,'note',to_jsonb(n));
END $$;
CREATE OR REPLACE FUNCTION public.audit_finalize_note_deletion(p_note_id text,p_owner_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE deleted integer;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 DELETE FROM public.notes WHERE note_id=p_note_id AND user_id=p_owner_id AND deleted_at IS NOT NULL AND deletion_started_at IS NOT NULL;
 GET DIAGNOSTICS deleted=ROW_COUNT;
 RETURN deleted=1;
END $$;
REVOKE ALL ON FUNCTION public.audit_claim_note_deletion(text,uuid,timestamptz),public.audit_finalize_note_deletion(text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_claim_note_deletion(text,uuid,timestamptz),public.audit_finalize_note_deletion(text,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.audit_guard_ai_dependencies() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() AND ((TG_OP='INSERT' AND NEW.context_dependencies IS NOT NULL) OR (TG_OP='UPDATE' AND NEW.context_dependencies IS DISTINCT FROM OLD.context_dependencies)) THEN
   RAISE EXCEPTION 'AI dependencies are server-managed' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER audit_guard_ai_dependencies BEFORE INSERT OR UPDATE ON public.ai_messages FOR EACH ROW EXECUTE FUNCTION public.audit_guard_ai_dependencies();
