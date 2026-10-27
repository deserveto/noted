-- Reservations exist before a copy starts, so interrupted copies remain visible.
CREATE TABLE public.audit_copy_cleanup_reservations (
 note_id text PRIMARY KEY,
 user_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','cleaning'))
);
REVOKE ALL ON public.audit_copy_cleanup_reservations FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.audit_copy_cleanup_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_migration_rollback_seal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_deletion_tombstones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deleting_accounts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.audit_guard_copy_reservation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE r public.audit_copy_cleanup_reservations%ROWTYPE;
BEGIN
 SELECT * INTO r FROM public.audit_copy_cleanup_reservations WHERE note_id=NEW.note_id FOR SHARE;
 IF FOUND AND (r.status<>'active' OR r.user_id<>NEW.user_id OR NOT public.is_privileged_context()) THEN
   RAISE EXCEPTION 'Copy reservation unavailable' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER audit_guard_copy_reservation BEFORE INSERT ON public.notes FOR EACH ROW EXECUTE FUNCTION public.audit_guard_copy_reservation();

CREATE OR REPLACE FUNCTION public.audit_reserve_copy_cleanup(p_note_id text,p_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_user_id::text,0));
 PERFORM public.audit_assert_account_active(p_user_id);
 IF p_note_id IS NULL OR p_note_id='' OR EXISTS(SELECT 1 FROM public.notes WHERE note_id=p_note_id) OR EXISTS(SELECT 1 FROM public.note_deletion_tombstones WHERE note_id=p_note_id) THEN RAISE EXCEPTION 'Copy ID unavailable' USING ERRCODE='55000'; END IF;
 INSERT INTO public.audit_copy_cleanup_reservations(note_id,user_id) VALUES(p_note_id,p_user_id);
END $$;
CREATE OR REPLACE FUNCTION public.audit_claim_copy_cleanup(p_note_id text,p_older_than timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE r public.audit_copy_cleanup_reservations%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.audit_copy_cleanup_reservations WHERE note_id=p_note_id FOR UPDATE;
 IF NOT FOUND OR p_older_than IS NULL OR r.created_at>p_older_than THEN RETURN jsonb_build_object('claimed',false); END IF;
 IF EXISTS(SELECT 1 FROM public.notes WHERE note_id=r.note_id) THEN
   DELETE FROM public.audit_copy_cleanup_reservations WHERE note_id=r.note_id;
   RETURN jsonb_build_object('claimed',false);
 END IF;
 INSERT INTO public.note_deletion_tombstones(note_id,owner_id) VALUES(r.note_id,r.user_id) ON CONFLICT(note_id) DO NOTHING;
 UPDATE public.audit_copy_cleanup_reservations SET status='cleaning' WHERE note_id=r.note_id;
 RETURN jsonb_build_object('claimed',true,'userId',r.user_id);
END $$;
CREATE OR REPLACE FUNCTION public.audit_finish_copy_cleanup(p_note_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 DELETE FROM public.audit_copy_cleanup_reservations WHERE note_id=p_note_id AND status='cleaning';
END $$;
CREATE OR REPLACE FUNCTION public.audit_complete_copy_cleanup(p_note_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE r public.audit_copy_cleanup_reservations%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.audit_copy_cleanup_reservations WHERE note_id=p_note_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF r.status<>'active' OR NOT EXISTS(SELECT 1 FROM public.notes WHERE note_id=r.note_id AND user_id=r.user_id) THEN RAISE EXCEPTION 'Copy not completed' USING ERRCODE='55000'; END IF;
 DELETE FROM public.audit_copy_cleanup_reservations WHERE note_id=p_note_id;
END $$;
CREATE OR REPLACE FUNCTION public.audit_list_copy_cleanup(p_older_than timestamptz,p_limit int)
RETURNS TABLE(note_id text,user_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_limit IS NULL OR p_limit<1 OR p_limit>1000 THEN RAISE EXCEPTION 'Invalid limit' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT r.note_id,r.user_id FROM public.audit_copy_cleanup_reservations r WHERE r.created_at<=p_older_than ORDER BY r.created_at,r.note_id LIMIT p_limit;
END $$;
REVOKE ALL ON FUNCTION public.audit_reserve_copy_cleanup(text,uuid),public.audit_claim_copy_cleanup(text,timestamptz),public.audit_finish_copy_cleanup(text),public.audit_complete_copy_cleanup(text),public.audit_list_copy_cleanup(timestamptz,int) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_reserve_copy_cleanup(text,uuid),public.audit_claim_copy_cleanup(text,timestamptz),public.audit_finish_copy_cleanup(text),public.audit_complete_copy_cleanup(text),public.audit_list_copy_cleanup(timestamptz,int) TO service_role;
