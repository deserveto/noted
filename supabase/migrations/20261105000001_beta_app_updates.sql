-- Release metadata is exposed only through the authenticated app-updates function.
-- Every valid signed-in account may use the beta; no enrollment table is needed.
-- APK storage remains private and download access is issued server-side.

CREATE FUNCTION public.valid_release_changelog(value jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN jsonb_typeof(value) = 'array' THEN
  jsonb_array_length(value) BETWEEN 1 AND 30 AND NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(value) entry WHERE
    jsonb_typeof(entry) IS DISTINCT FROM 'object' OR
    entry->>'type' IS NULL OR entry->>'type' NOT IN ('added','changed','fixed') OR
    jsonb_typeof(entry->'text') IS DISTINCT FROM 'string' OR
    char_length(trim(entry->>'text')) NOT BETWEEN 1 AND 500
  ) ELSE false END
$$;

CREATE TABLE public.app_releases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 platform text NOT NULL CHECK (platform = 'android'),
 channel text NOT NULL CHECK (channel = 'beta'),
 distribution text NOT NULL CHECK (distribution = 'direct_apk'),
 version text NOT NULL CHECK (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$' AND char_length(version) <= 40),
 build_number integer NOT NULL CHECK (build_number BETWEEN 1 AND 2100000000),
 changelog jsonb NOT NULL CHECK (public.valid_release_changelog(changelog)),
 published_at timestamptz,
 state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','withdrawn')),
 object_path text NOT NULL UNIQUE,
 size_bytes bigint NOT NULL CHECK (size_bytes BETWEEN 1 AND 536870912),
 sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
 min_sdk integer NOT NULL CHECK (min_sdk BETWEEN 24 AND 1000),
 artifact_verified_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (platform, channel, distribution, build_number),
 CHECK (object_path = platform || '/' || channel || '/' || version || '/' || build_number::text || '/noted-' || version || '-build-' || build_number::text || '.apk'),
 CHECK ((state = 'draft' AND published_at IS NULL AND artifact_verified_at IS NULL) OR
        (state IN ('published','withdrawn') AND published_at IS NOT NULL AND artifact_verified_at IS NOT NULL))
);
CREATE INDEX app_releases_available ON public.app_releases(platform, channel, distribution, build_number DESC) WHERE state='published';
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_releases FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_releases TO service_role;
REVOKE ALL ON FUNCTION public.valid_release_changelog(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.valid_release_changelog(jsonb) TO service_role;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('app-releases','app-releases',false,536870912,ARRAY['application/vnd.android.package-archive'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=EXCLUDED.file_size_limit,allowed_mime_types=EXCLUDED.allowed_mime_types;
-- Deliberately no client storage policy. Signed links are issued server-side only.

CREATE FUNCTION public.guard_app_release() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.published_at IS NOT NULL THEN RAISE EXCEPTION 'Published releases must be retained'; END IF;
  RETURN OLD;
 END IF;
 IF OLD.published_at IS NOT NULL THEN
  IF NEW.state NOT IN ('published','withdrawn') OR
     (OLD.state='withdrawn' AND NEW.state <> 'withdrawn') OR
     (to_jsonb(NEW)-'state') IS DISTINCT FROM (to_jsonb(OLD)-'state') THEN
   RAISE EXCEPTION 'Published release identity and metadata are immutable';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER guard_app_release BEFORE UPDATE OR DELETE ON public.app_releases FOR EACH ROW EXECUTE FUNCTION public.guard_app_release();

-- Retain published artifacts indefinitely. This includes withdrawals, so already
-- issued links can finish downloading and a versioned path is never reused.
CREATE FUNCTION public.guard_release_artifact() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF OLD.bucket_id='app-releases' AND EXISTS (
  SELECT 1 FROM public.app_releases WHERE object_path=OLD.name AND published_at IS NOT NULL
 ) THEN RAISE EXCEPTION 'Published APK artifacts are immutable and retained'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER guard_release_artifact BEFORE UPDATE OR DELETE ON storage.objects FOR EACH ROW EXECUTE FUNCTION public.guard_release_artifact();

-- The trusted publisher verifies a downloaded binary's size and hash before
-- this final transaction. No client can invoke publication or mutate metadata.
CREATE FUNCTION public.publish_app_release(p_release_id uuid,p_size_bytes bigint,p_sha256 text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE release public.app_releases%ROWTYPE;
BEGIN
 IF NOT public.is_privileged_context() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
 -- Serialize publication so two builds cannot race the monotonic check.
 LOCK TABLE public.app_releases IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO release FROM public.app_releases WHERE id=p_release_id FOR UPDATE;
 IF NOT FOUND OR release.state <> 'draft' THEN RAISE EXCEPTION 'A draft release is required'; END IF;
 IF p_size_bytes IS DISTINCT FROM release.size_bytes OR p_sha256 IS DISTINCT FROM release.sha256 THEN
  RAISE EXCEPTION 'Artifact verification mismatch';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='app-releases' AND name=release.object_path AND metadata->>'size'=release.size_bytes::text) THEN
  RAISE EXCEPTION 'Verified APK object is unavailable or has an unexpected size';
 END IF;
 IF EXISTS (SELECT 1 FROM public.app_releases r WHERE r.platform=release.platform AND r.channel=release.channel AND r.distribution=release.distribution AND r.published_at IS NOT NULL AND r.build_number >= release.build_number) THEN
  RAISE EXCEPTION 'Release build must increase monotonically';
 END IF;
 UPDATE public.app_releases SET state='published',published_at=now(),artifact_verified_at=now() WHERE id=p_release_id RETURNING * INTO release;
 RETURN to_jsonb(release);
END $$;
REVOKE ALL ON FUNCTION public.publish_app_release(uuid,bigint,text),public.guard_app_release(),public.guard_release_artifact() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.publish_app_release(uuid,bigint,text),public.guard_app_release(),public.guard_release_artifact() TO service_role;

CREATE FUNCTION public.app_release_artifact_available(p_release_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS (
  SELECT 1 FROM public.app_releases r JOIN storage.objects o
   ON o.bucket_id='app-releases' AND o.name=r.object_path
  WHERE r.id=p_release_id AND r.state='published' AND r.published_at<=now()
   AND o.metadata->>'size'=r.size_bytes::text
 )
$$;
REVOKE ALL ON FUNCTION public.app_release_artifact_available(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.app_release_artifact_available(uuid) TO service_role;
