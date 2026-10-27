-- AI authorization and persistence share one transaction and row locks.
CREATE OR REPLACE FUNCTION public.audit_commit_ai_exchange(
 p_user_id uuid,p_dependencies text[],p_chat_id text,p_title text,p_scope jsonb,
 p_prompt text,p_answer jsonb,p_persist boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE dep text; n public.notes%ROWTYPE; message_id text;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_user_id IS NULL OR p_dependencies IS NULL OR array_position(p_dependencies,NULL) IS NOT NULL OR p_persist IS NULL THEN RAISE EXCEPTION 'Invalid AI request' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_user_id::text,0));
 PERFORM public.audit_assert_account_active(p_user_id);
 FOR dep IN SELECT DISTINCT d FROM unnest(p_dependencies) d ORDER BY d LOOP
   SELECT * INTO n FROM public.notes WHERE note_id=dep FOR SHARE;
   IF NOT FOUND OR n.deleted_at IS NOT NULL OR n.deletion_started_at IS NOT NULL OR NOT (n.user_id=p_user_id OR p_user_id=ANY(n.live_member_ids)) THEN
     RAISE EXCEPTION 'Access to a supplied note changed' USING ERRCODE='42501';
   END IF;
   PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || n.user_id::text,0));
   PERFORM public.audit_assert_account_active(n.user_id);
 END LOOP;
 IF p_persist THEN
   IF p_chat_id IS NULL OR p_chat_id='' OR p_prompt IS NULL OR jsonb_typeof(p_scope) IS DISTINCT FROM 'object' OR jsonb_typeof(p_answer) IS DISTINCT FROM 'object' OR jsonb_typeof(p_answer->'blocks') IS DISTINCT FROM 'array' OR jsonb_typeof(p_answer->'sources') IS DISTINCT FROM 'array' THEN
     RAISE EXCEPTION 'Invalid AI exchange' USING ERRCODE='22023';
   END IF;
   INSERT INTO public.ai_chats(user_id,chat_id,title,scope,updated_at)
   VALUES(p_user_id,p_chat_id,COALESCE(p_title,'New chat'),p_scope,now())
   ON CONFLICT(user_id,chat_id) DO UPDATE SET title=EXCLUDED.title,scope=EXCLUDED.scope,updated_at=EXCLUDED.updated_at;
   INSERT INTO public.ai_messages(user_id,chat_id,role,text,context_dependencies,created_at)
   VALUES(p_user_id,p_chat_id,'user',p_prompt,to_jsonb(p_dependencies),now());
   INSERT INTO public.ai_messages(user_id,chat_id,role,blocks,sources,intent,context_dependencies,created_at)
   VALUES(p_user_id,p_chat_id,'ai',p_answer->'blocks',p_answer->'sources',p_answer->>'intent',to_jsonb(p_dependencies),now()+interval '1 millisecond') RETURNING id INTO message_id;
 END IF;
 RETURN jsonb_build_object('messageId',message_id);
END $$;
REVOKE ALL ON FUNCTION public.audit_commit_ai_exchange(uuid,text[],text,text,jsonb,text,jsonb,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_commit_ai_exchange(uuid,text[],text,text,jsonb,text,jsonb,boolean) TO service_role;

-- Abandoned paths remain scheduled for re-sweeps even after first cleanup.
CREATE TABLE public.audit_copy_sweeps(note_id text PRIMARY KEY,user_id uuid NOT NULL,last_attempted_at timestamptz);
ALTER TABLE public.audit_copy_sweeps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.audit_copy_sweeps FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.audit_register_copy_sweep() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NEW.status='cleaning' AND OLD.status IS DISTINCT FROM 'cleaning' THEN
   INSERT INTO public.audit_copy_sweeps(note_id,user_id) VALUES(NEW.note_id,NEW.user_id) ON CONFLICT(note_id) DO NOTHING;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER audit_register_copy_sweep AFTER UPDATE ON public.audit_copy_cleanup_reservations FOR EACH ROW EXECUTE FUNCTION public.audit_register_copy_sweep();
CREATE OR REPLACE FUNCTION public.audit_list_copy_sweeps(p_limit int) RETURNS TABLE(note_id text,user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_limit IS NULL OR p_limit<1 OR p_limit>1000 THEN RAISE EXCEPTION 'Invalid limit' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT s.note_id,s.user_id FROM public.audit_copy_sweeps s WHERE NOT EXISTS(SELECT 1 FROM public.notes n WHERE n.note_id=s.note_id) ORDER BY s.last_attempted_at ASC NULLS FIRST,s.note_id LIMIT p_limit;
END $$;
CREATE OR REPLACE FUNCTION public.audit_record_copy_sweep(p_note_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 UPDATE public.audit_copy_sweeps SET last_attempted_at=clock_timestamp() WHERE note_id=p_note_id;
END $$;
REVOKE ALL ON FUNCTION public.audit_list_copy_sweeps(int),public.audit_record_copy_sweep(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_list_copy_sweeps(int),public.audit_record_copy_sweep(text) TO service_role;
