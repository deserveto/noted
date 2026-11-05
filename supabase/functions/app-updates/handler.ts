import { requireAuthenticatedUser, type VerifyBearerToken } from '../_shared/auth.ts';
import { AppError, errorResponse, handleCorsPreflight, jsonResponse as json } from '../_shared/cors.ts';

function noStore(response: Response): Response {
  response.headers.set('Cache-Control','private, no-store');
  return response;
}
function jsonResponse(body: unknown): Response { return noStore(json(body)); }

export interface AppRelease {
  id: string;
  platform: string;
  channel: string;
  distribution: string;
  version: string;
  build_number: number;
  changelog: {type: string; text: string}[];
  published_at: string | null;
  state: string;
  object_path: string;
  size_bytes: number;
  sha256: string;
  min_sdk: number;
}
export interface UpdatesStore {
  listReleases(channel: string, sdk: number, releaseId?: string, installedBuild?: number): Promise<AppRelease[]>;
  artifactAvailable(release: AppRelease): Promise<boolean>;
  signDownload(release: AppRelease, seconds: number): Promise<string>;
}
const fields = 'id,platform,channel,distribution,version,build_number,changelog,published_at,state,object_path,size_bytes,sha256,min_sdk';
// deno-lint-ignore no-explicit-any
export function createSupabaseUpdatesStore(admin: any): UpdatesStore {
  return {
    async listReleases(channel, sdk, releaseId, installedBuild) {
      let query = admin.from('app_releases').select(fields).eq('platform','android').eq('channel',channel).eq('distribution','direct_apk').eq('state','published').lte('min_sdk',sdk).lte('published_at',new Date().toISOString()).order('build_number',{ascending:false});
      if (releaseId) query = query.eq('id',releaseId);
      // Filter before limiting: installed release notes may be older than the
      // latest 50 releases, especially after a long period offline.
      if (installedBuild !== undefined) query = query.eq('build_number',installedBuild);
      const {data,error} = await query.limit(50);
      if (error) throw error;
      return data ?? [];
    },
    async artifactAvailable(release) {
      // storage is not an exposed PostgREST schema. Use a service-only RPC.
      const {data,error} = await admin.rpc('app_release_artifact_available',{p_release_id:release.id});
      if (error) throw error;
      return data === true;
    },
    async signDownload(release, seconds) {
      const {data,error} = await admin.storage.from('app-releases').createSignedUrl(release.object_path,seconds,{download: release.object_path.split('/').at(-1)});
      if (error || !data?.signedUrl) throw new AppError('unavailable','The update download is unavailable. Try again.');
      return data.signedUrl;
    },
  };
}

function eligible(release: AppRelease, sdk: number, now: number): boolean {
  return release.platform === 'android' && release.channel === 'beta' && release.distribution === 'direct_apk' &&
    release.state === 'published' && typeof release.published_at === 'string' && Date.parse(release.published_at) <= now &&
    Number.isInteger(release.build_number) && release.build_number > 0 && Number.isInteger(release.min_sdk) && release.min_sdk <= sdk;
}

export async function handleAppUpdatesRequest(req: Request, deps: {verifyToken: VerifyBearerToken; store: UpdatesStore}): Promise<Response> {
  const cors = handleCorsPreflight(req); if (cors) return cors;
  try {
    if (req.method !== 'POST') throw new AppError('invalid-argument','Use POST.');
    // Beta enrollment is open to every valid signed-in account. The runtime
    // verifier calls Supabase Auth getUser(jwt), rather than trusting claims
    // or a client-selected channel as proof of authentication.
    await requireAuthenticatedUser(req,deps.verifyToken);
    let payload;
    try { payload = await req.json(); } catch { throw new AppError('invalid-argument','Invalid request.'); }
    if (!payload || payload.platform !== 'android' || payload.channel !== 'beta' || payload.distribution !== 'direct_apk' ||
        !Number.isInteger(payload.build_number) || payload.build_number < 1 || payload.build_number > 2100000000 ||
        !Number.isInteger(payload.sdk_int) || payload.sdk_int < 24 || payload.sdk_int > 1000 ||
        !['check','history','download'].includes(payload.action)) throw new AppError('invalid-argument','Unsupported update request.');
    if ('installed_only' in payload && (typeof payload.installed_only !== 'boolean' || payload.action !== 'history')) throw new AppError('invalid-argument','Installed-only filtering is supported for release history.');
    if (payload.action === 'download' && (typeof payload.release_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(payload.release_id))) throw new AppError('invalid-argument','Invalid release.');
    const now = Date.now();
    const installedBuild = payload.action === 'history' && payload.installed_only === true ? payload.build_number : undefined;
    const rows = (await deps.store.listReleases(payload.channel,payload.sdk_int,payload.action === 'download' ? payload.release_id : undefined,installedBuild))
      .filter(release => eligible(release,payload.sdk_int,now) && (payload.action === 'history' || release.build_number > payload.build_number) && (payload.action !== 'download' || release.id === payload.release_id) && (installedBuild === undefined || release.build_number === installedBuild))
      .sort((a,b) => b.build_number-a.build_number).slice(0,50);
    const available: AppRelease[] = [];
    for (const release of rows) {
      if (await deps.store.artifactAvailable(release)) {
        available.push(release);
        if (payload.action !== 'history') break;
      }
    }
    if (payload.action === 'history') return jsonResponse({releases:available});
    if (payload.action === 'check') return jsonResponse({release:available[0] ?? null});
    const release = available[0];
    if (!release) throw new AppError('not-found','This update is no longer available. Check for updates again.');
    return jsonResponse({url:await deps.store.signDownload(release,900)});
  } catch (error) {
    return noStore(errorResponse(error instanceof AppError ? error : new AppError('unavailable','Updates are unavailable. Check your connection and try again.')));
  }
}
