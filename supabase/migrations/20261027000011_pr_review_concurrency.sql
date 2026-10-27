-- Serialize a source authorization check with duplicate insertion.
CREATE OR REPLACE FUNCTION public.audit_duplicate_note(p_note_id text,p_actor_id uuid,p_expected_revision int,p_copy jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE n public.notes%ROWTYPE; copied public.notes%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('noted-account:' || p_actor_id::text,0));
 PERFORM public.audit_assert_account_active(p_actor_id);
 SELECT * INTO n FROM public.notes WHERE note_id=p_note_id FOR SHARE;
 IF NOT FOUND OR n.deleted_at IS NOT NULL OR n.deletion_started_at IS NOT NULL OR NOT (n.user_id=p_actor_id OR p_actor_id=ANY(n.live_member_ids)) THEN RAISE EXCEPTION 'Source access changed' USING ERRCODE='42501'; END IF;
 PERFORM public.audit_assert_account_active(n.user_id);
 IF n.revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'Source changed; retry copy' USING ERRCODE='40001'; END IF;
 INSERT INTO public.notes(note_id,user_id,owner_name,owner_email,title,content,category,color,is_favorite,source_owner_id,source_note_id,attachments,last_edited_by)
 VALUES(p_copy->>'note_id',p_actor_id,COALESCE(p_copy->>'owner_name',''),COALESCE(p_copy->>'owner_email',''),COALESCE(p_copy->>'title',''),COALESCE(p_copy->>'content',''),COALESCE(p_copy->>'category','Personal'),COALESCE(p_copy->>'color','blue'),false,NULLIF(p_copy->>'source_owner_id','')::uuid,NULLIF(p_copy->>'source_note_id',''),COALESCE(p_copy->'attachments','[]'::jsonb),p_actor_id) RETURNING * INTO copied;
 RETURN jsonb_build_object('note',to_jsonb(copied));
END $$;
REVOKE ALL ON FUNCTION public.audit_duplicate_note(text,uuid,int,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_duplicate_note(text,uuid,int,jsonb) TO service_role;

-- All history commits and clears serialize on the same per-account lock.
CREATE OR REPLACE FUNCTION public.audit_clear_ai_history(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('noted-ai:' || p_user_id::text,0));
 UPDATE public.ai_requests SET cancelled=true,status='cancelled',updated_at=now() WHERE user_id=p_user_id AND status='running';
 DELETE FROM public.ai_chats WHERE user_id=p_user_id;
END $$;
REVOKE ALL ON FUNCTION public.audit_clear_ai_history(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_clear_ai_history(uuid) TO service_role;

DROP FUNCTION public.audit_commit_ai_exchange(uuid,text[],text,text,jsonb,text,jsonb,boolean);
CREATE OR REPLACE FUNCTION public.audit_commit_ai_exchange(
 p_user_id uuid,p_request_id text,p_dependencies text[],p_chat_id text,p_title text,p_scope jsonb,
 p_prompt text,p_answer jsonb,p_persist boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE dep text; n public.notes%ROWTYPE; message_id text; request_row public.ai_requests%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_user_id IS NULL OR p_dependencies IS NULL OR array_position(p_dependencies,NULL) IS NOT NULL OR p_persist IS NULL THEN RAISE EXCEPTION 'Invalid AI request' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('noted-ai:' || p_user_id::text,0));
 SELECT * INTO request_row FROM public.ai_requests WHERE user_id=p_user_id AND request_id=p_request_id FOR UPDATE;
 IF NOT FOUND OR request_row.cancelled OR request_row.status <> 'running' THEN RAISE EXCEPTION 'AI request cancelled' USING ERRCODE='57014'; END IF;
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
 UPDATE public.ai_requests SET status='completed',completed_at=now(),updated_at=now() WHERE user_id=p_user_id AND request_id=p_request_id;
 RETURN jsonb_build_object('messageId',message_id);
END $$;
REVOKE ALL ON FUNCTION public.audit_commit_ai_exchange(uuid,text,text[],text,text,jsonb,text,jsonb,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_commit_ai_exchange(uuid,text,text[],text,text,jsonb,text,jsonb,boolean) TO service_role;
