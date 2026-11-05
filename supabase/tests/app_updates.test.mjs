import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupabaseUpdatesStore, handleAppUpdatesRequest } from '../functions/app-updates/handler.ts';
import { createSupabaseTestDb } from './pglite_supabase_harness.mjs';

const UID = '11111111-1111-4111-8111-111111111111';
const RID = '22222222-2222-4222-8222-222222222222';
const hash = 'a'.repeat(64);
const release = (patch = {}) => ({id: RID, platform: 'android', channel: 'beta', distribution: 'direct_apk', version: '2.0.1', build_number: 5, changelog: [{type: 'fixed', text: 'Reliable beta updates.'}], published_at: '2026-01-01T00:00:00Z', state: 'published', object_path: 'android/beta/2.0.1/5/noted-2.0.1-build-5.apk', size_bytes: 1234, sha256: hash, min_sdk: 24, ...patch});
const body = (patch = {}) => ({action: 'check', platform: 'android', channel: 'beta', distribution: 'direct_apk', build_number: 3, sdk_int: 35, ...patch});
const req = (payload, token = 'valid') => new Request('https://example.supabase.co/functions/v1/app-updates', {method: 'POST', headers: token ? {Authorization: `Bearer ${token}`} : {}, body: JSON.stringify(payload)});
function deps(patch = {}) {
  return {verifyToken: async token => token === 'valid' ? {uid: UID, email: ''} : token === 'new-signup' ? {uid: '33333333-3333-4333-8333-333333333333', email: 'new@example.com'} : null, store: {listReleases: async () => [release()], artifactAvailable: async () => true, signDownload: async () => 'https://example.supabase.co/storage/v1/object/sign/app-releases/test.apk?token=secret', ...patch}};
}
test('every valid signed-in account can use beta updates without enrollment; anonymous and invalid sessions are denied', async () => {
  for (const action of ['check','history','download']) {
    const payload = body({action, ...(action === 'download' ? {release_id: RID} : {})});
    for (const token of ['valid', 'new-signup']) {
      assert.equal((await handleAppUpdatesRequest(req(payload,token),deps())).status,200);
    }
    for (const token of [null,'expired-or-invalid']) {
      let queried = false;
      const response = await handleAppUpdatesRequest(req(payload,token),deps({listReleases: async () => { queried = true; return []; }}));
      assert.equal(response.status,401);
      assert.equal(queried,false);
    }
  }
  assert.equal((await handleAppUpdatesRequest(req(body({channel: 'stable'})), deps())).status, 400);
});
test('check chooses highest eligible numeric build and excludes incompatible or unpublished releases', async () => {
  const rows = [release({build_number: 10}), release({build_number: 99, state: 'draft'}), release({build_number: 98, state: 'withdrawn'}), release({build_number: 97, min_sdk: 36}), release({build_number: 96, platform: 'ios'}), release({build_number: 95, channel: 'stable'}), release({build_number: 94, distribution: 'store'}), release({build_number: 93, published_at: '2999-01-01T00:00:00Z'}), release()];
  const response = await handleAppUpdatesRequest(req(body()), deps({listReleases: async () => rows}));
  assert.equal((await response.json()).release.build_number, 10);
  const none = await handleAppUpdatesRequest(req(body({build_number: 10})), deps({listReleases: async () => rows}));
  assert.equal((await none.json()).release, null);
});
test('release history is authorized, includes installed builds, and hides unavailable artifacts', async () => {
  const response = await handleAppUpdatesRequest(req(body({action: 'history', build_number: 20})), deps());
  assert.equal((await response.json()).releases.length, 1);
  assert.equal((await handleAppUpdatesRequest(req(body({action: 'history'}),null), deps())).status, 401);
  const missing = await handleAppUpdatesRequest(req(body()), deps({artifactAvailable: async () => false}));
  assert.equal((await missing.json()).release, null);
});
test('installed-only history queries the exact installed build and filters other results', async () => {
  let args;
  const d = deps({listReleases: async (...values) => {
    args = values;
    return [release({build_number: 100}), release({build_number: 3}), release()];
  }});
  const response = await handleAppUpdatesRequest(req(body({action: 'history', installed_only: true})), d);
  assert.equal(response.status, 200);
  assert.deepEqual(args, ['beta', 35, undefined, 3]);
  assert.deepEqual((await response.json()).releases.map(r => r.build_number), [3]);
  await handleAppUpdatesRequest(req(body({action: 'history', installed_only: false})), d);
  assert.deepEqual(args, ['beta', 35, undefined, undefined]);
  for (const patch of [{action: 'history', installed_only: 'true'}, {installed_only: true}, {installed_only: false}]) {
    assert.equal((await handleAppUpdatesRequest(req(body(patch)), d)).status, 400);
  }
});
test('installed-only storage query applies the exact build filter before limiting history', async () => {
  const calls = [];
  const query = {then: resolve => resolve({data: []})};
  for (const method of ['select', 'eq', 'lte', 'order', 'limit']) {
    query[method] = (...args) => {calls.push([method, ...args]); return query;};
  }
  const store = createSupabaseUpdatesStore({from: () => query});
  await store.listReleases('beta',35,undefined,3);
  const filter = calls.findIndex(call => call[0] === 'eq' && call[1] === 'build_number' && call[2] === 3);
  assert.ok(filter >= 0);
  assert.ok(filter < calls.findIndex(call => call[0] === 'limit'));
});
test('download checks publication, compatibility and availability; links expire after 15 minutes', async () => {
  let seconds;
  const d = deps({signDownload: async (_, ttl) => { seconds = ttl; return 'https://example.supabase.co/storage/v1/object/sign/app-releases/test.apk?token=secret'; }});
  const response = await handleAppUpdatesRequest(req(body({action: 'download', release_id: RID})), d);
  assert.equal(response.status, 200); assert.equal(seconds, 900);
  for (const patch of [{state: 'withdrawn'}, {min_sdk: 36}, {build_number: 3}]) {
    assert.equal((await handleAppUpdatesRequest(req(body({action: 'download', release_id: RID})), deps({listReleases: async () => [release(patch)]}))).status, 404);
  }
  assert.equal((await handleAppUpdatesRequest(req(body({action: 'download', release_id: RID})), deps({artifactAvailable: async () => false}))).status, 404);
  assert.equal((await handleAppUpdatesRequest(req(body({action: 'download', release_id: RID}),'invalid'), deps())).status, 401);
});
test('malformed requests and backend failures fail safely without leaking signed URLs or errors', async () => {
  for (const patch of [{build_number: '3'}, {sdk_int: -1}, {action: 'publish'}, {action: 'download', release_id: '../foo'}]) {
    assert.equal((await handleAppUpdatesRequest(req(body(patch)), deps())).status, 400);
  }
  const response = await handleAppUpdatesRequest(req(body()), deps({listReleases: async () => {throw new Error('private credentials');}}));
  assert.equal(response.status, 503); assert.doesNotMatch(await response.text(), /private credentials/);
});

test('release RLS, publication guards, monotonic builds and artifact retention', async () => {
  const c = await createSupabaseTestDb();
  try {
    await c.createAuthUser({id: UID, email: 'tester@example.com', name: 'Tester'});
    assert.equal((await c.db.query("select to_regclass('public.release_testers') as table_name")).rows[0].table_name,null);
    await assert.rejects(() => c.asUser(UID, t => t.query('select * from app_releases')));
    await assert.rejects(() => c.asAnon(t => t.query('select * from app_releases')));
    await assert.rejects(() => c.asUser(UID, t => t.query('select publish_app_release($1,1234,$2)', [RID, hash])));
    await assert.rejects(() => c.asUser(UID, t => t.query('select app_release_artifact_available($1)', [RID])));
    await assert.rejects(() => c.asUser(UID, t => t.query("insert into storage.objects(bucket_id,name) values('app-releases','rogue.apk')")));
    await c.asService(t => t.query(`insert into app_releases(id, platform, channel, distribution, version, build_number, changelog, object_path, size_bytes, sha256, min_sdk) values($1,'android','beta','direct_apk','2.0.1',5,'[{"type":"fixed","text":"Update"}]','android/beta/2.0.1/5/noted-2.0.1-build-5.apk',1234,$2,24)`, [RID, hash]));
    const publish = (size = 1234, checksum = hash) => c.asService(t => t.query('select publish_app_release($1,$2,$3)', [RID, size, checksum]));
    await assert.rejects(() => publish());
    await c.asService(t => t.query("insert into storage.objects(bucket_id,name,metadata) values('app-releases','android/beta/2.0.1/5/noted-2.0.1-build-5.apk','{\"size\":1234}')"));
    await assert.rejects(() => publish(1235)); await assert.rejects(() => publish(1234, 'b'.repeat(64)));
    assert.equal((await c.asUser(UID, t => t.query("select * from storage.objects where bucket_id='app-releases'"))).rows.length, 0);
    await publish();
    assert.equal((await c.asService(t => t.query('select app_release_artifact_available($1) as available', [RID]))).rows[0].available, true);
    await assert.rejects(() => c.asService(t => t.query("update app_releases set sha256=$1 where id=$2", ['b'.repeat(64), RID])));
    await assert.rejects(() => c.asService(t => t.query("update app_releases set state='draft' where id=$1", [RID])));
    await assert.rejects(() => c.asService(t => t.query("delete from storage.objects where bucket_id='app-releases'")));
    await assert.rejects(() => c.asService(t => t.query("update storage.objects set metadata='{}' where bucket_id='app-releases'")));
    await c.asService(t => t.query("update app_releases set state='withdrawn' where id=$1", [RID]));
    assert.equal((await c.asService(t => t.query('select app_release_artifact_available($1) as available', [RID]))).rows[0].available, false);
    await assert.rejects(() => publish());
    await assert.rejects(() => c.asService(t => t.query('delete from app_releases where id=$1', [RID])));
    await assert.rejects(() => c.asService(t => t.query("update app_releases set state='published' where id=$1", [RID])));
    await assert.rejects(() => c.asService(t => t.query(`insert into app_releases(platform,channel,distribution,version,build_number,changelog,object_path,size_bytes,sha256,min_sdk) values('android','beta','direct_apk','2.0.1',6,'[]','wrong.apk',1234,$1,24)`, [hash])));
    for (const build of [4, 6]) {
      const path = `android/beta/2.0.1/${build}/noted-2.0.1-build-${build}.apk`;
      const result = await c.asService(t => t.query(`insert into app_releases(platform,channel,distribution,version,build_number,changelog,object_path,size_bytes,sha256,min_sdk) values('android','beta','direct_apk','2.0.1',$1,'[{"type":"fixed","text":"Correction"}]',$2,1234,$3,24) returning id`, [build,path,hash]));
      await c.asService(t => t.query("insert into storage.objects(bucket_id,name,metadata) values('app-releases',$1,'{\"size\":1234}')", [path]));
      const action = () => c.asService(t => t.query('select publish_app_release($1,1234,$2)', [result.rows[0].id,hash]));
      if (build === 4) await assert.rejects(action); else await action();
    }
  } finally { await c.db.close(); }
});
