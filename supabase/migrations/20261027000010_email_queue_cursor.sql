-- Durable scan position prevents a long quiet-hours prefix starving later mail.
CREATE TABLE public.audit_email_cursor (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 created_at timestamptz,
 notification_id text
);
ALTER TABLE public.audit_email_cursor ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.audit_email_cursor FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.audit_take_email_batch(p_limit int)
RETURNS TABLE(id text,user_id uuid,type text,title text,body text,note_id text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_catalog AS $$
DECLARE v_created_at timestamptz; v_id text; batch jsonb; tail jsonb;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN RAISE EXCEPTION 'Invalid batch limit' USING ERRCODE='22023'; END IF;
 INSERT INTO public.audit_email_cursor(id) VALUES(true) ON CONFLICT DO NOTHING;
 SELECT c.created_at,c.notification_id INTO v_created_at,v_id FROM public.audit_email_cursor c WHERE c.id=true FOR UPDATE;
 SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.created_at,q.id),'[]'::jsonb) INTO batch FROM (
   SELECT n.id,n.user_id,n.type,n.title,n.body,n.note_id,n.created_at FROM public.notifications n
   WHERE NOT n.email_dispatched AND (v_created_at IS NULL OR (n.created_at,n.id)>(v_created_at,v_id))
   ORDER BY n.created_at,n.id LIMIT p_limit
 ) q;
 IF jsonb_array_length(batch)=0 AND v_created_at IS NOT NULL THEN
   SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.created_at,q.id),'[]'::jsonb) INTO batch FROM (
     SELECT n.id,n.user_id,n.type,n.title,n.body,n.note_id,n.created_at FROM public.notifications n
     WHERE NOT n.email_dispatched ORDER BY n.created_at,n.id LIMIT p_limit
   ) q;
 END IF;
 IF jsonb_array_length(batch)>0 THEN
   tail:=batch->(jsonb_array_length(batch)-1);
   UPDATE public.audit_email_cursor SET created_at=(tail->>'created_at')::timestamptz,notification_id=tail->>'id' WHERE audit_email_cursor.id=true;
 END IF;
 RETURN QUERY SELECT x.id,x.user_id,x.type,x.title,x.body,x.note_id FROM jsonb_to_recordset(batch)
   AS x(id text,user_id uuid,type text,title text,body text,note_id text,created_at timestamptz) ORDER BY x.created_at,x.id;
END $$;
REVOKE ALL ON FUNCTION public.audit_take_email_batch(int) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.audit_take_email_batch(int) TO service_role;
