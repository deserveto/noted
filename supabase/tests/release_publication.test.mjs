import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import { readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseApkIdentity, validateChangelog, publishRelease, createReleaseStore, inspectApk } from '../../tools/releases/release.mjs';

const bytes = Buffer.from('verified APK binary');
const artifact = {
  version: '2.0.1', build_number: 5, min_sdk: 24,
  size_bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), bytes,
};
const changelog = [{ type: 'fixed', text: 'Preserve offline notes when reconnecting.' }];

test('inspection verifies a fixed snapshot and uploads its bytes even if a build replaces the input', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'noted-release-test-'));
  const apk = path.join(directory, 'mutable.apk');
  const cert = 'ab'.repeat(32);
  let snapshot;
  try {
    await fs.writeFile(apk, bytes);
    const result = await inspectApk({ apk, version: '2.0.1', build: 5, certificate: cert, buildTools: directory }, (_command, args) => {
      snapshot = args.at(-1);
      assert.notEqual(snapshot, apk);
      writeFileSync(apk, 'replacement from another build');
      assert.deepEqual(readFileSync(snapshot), bytes);
      return args.includes('badging')
        ? "package: name='com.noted.app' versionCode='5' versionName='2.0.1'\nsdkVersion:'24'\nnative-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'"
        : `Signer #1 certificate SHA-256 digest: ${cert}`;
    });
    assert.deepEqual(result.bytes, bytes);
    assert.equal(result.sha256, artifact.sha256);
    await assert.rejects(fs.access(snapshot));
    await fs.writeFile(apk, bytes);
    await assert.rejects(inspectApk({ apk, version: '2.0.1', build: 5, certificate: cert, buildTools: directory }, (_command, args) => {
      snapshot = args.at(-1);
      throw Error('verification failure');
    }));
    await assert.rejects(fs.access(snapshot));
  } finally {
    await fs.unlink(apk);
    await fs.rmdir(directory);
  }
});

test('version metadata respects the database length bound before upload', async () => {
  const version = `${'1'.repeat(37)}.0.0`;
  const store = fakeStore();
  await assert.rejects(publishRelease({ artifact: { ...artifact, version }, changelog, store }));
  assert.deepEqual(store.calls, []);
  const badging = `package: name='com.noted.app' versionCode='5' versionName='${version}'\nsdkVersion:'24'\nnative-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'`;
  assert.throws(() => parseApkIdentity(badging, `Signer #1 certificate SHA-256 digest: ${'ab'.repeat(32)}`, { version, build: 5, certificate: 'ab'.repeat(32) }));
});
function fakeStore(fail = '') {
  const calls = [];
  return {
    calls, existing: null, highest: 3,
    async findBuild() { return this.existing; },
    async highestBuild() { return this.highest; },
    async upload(path, value) { calls.push('upload'); if (fail === 'upload') throw Error('upload failed'); assert.deepEqual(value, bytes); },
    async insertDraft(row) { calls.push('draft'); if (fail === 'draft') throw Error('draft failed'); return { ...row, id: 'release-id' }; },
    async download() { calls.push('download'); if (fail === 'download') throw Error('download failed'); return fail === 'hash' ? Buffer.alloc(bytes.length) : fail === 'size' ? Buffer.from('wrong') : bytes; },
    async publish(id, size, hash) { calls.push('publish'); if (fail === 'publish') throw Error('publish failed'); assert.equal(size, bytes.length); assert.equal(hash, artifact.sha256); return { id, state: 'published' }; },
  };
}

test('APK identity verifies numeric build, SDK, app ID and pinned certificate', () => {
  const cert = 'ab'.repeat(32);
  const badging = "package: name='com.noted.app' versionCode='5' versionName='2.0.1'\nsdkVersion:'24'\nnative-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'";
  const result = parseApkIdentity(badging, `Signer #1 certificate SHA-256 digest: ${cert}`, { version: '2.0.1', build: 5, certificate: cert });
  assert.deepEqual(result, { version: '2.0.1', build_number: 5, min_sdk: 24 });
  for (const changed of [badging.replace('com.noted.app', 'bad.app'), badging.replace("'5'", "'4'"), badging.replace("'2.0.1'", "'2.0.2'"), badging.replace("'24'", "'bad'"), badging.replace("'24'", "'23'"), badging.replace(" 'x86_64'", ''), `${badging}\nuses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'`]) {
    assert.throws(() => parseApkIdentity(changed, `Signer #1 certificate SHA-256 digest: ${cert}`, { version: '2.0.1', build: 5, certificate: cert }));
  }
  assert.throws(() => parseApkIdentity(badging, `Signer #1 certificate SHA-256 digest: ${'cd'.repeat(32)}`, { version: '2.0.1', build: 5, certificate: cert }));
  assert.throws(() => parseApkIdentity(badging, '', { version: '2.0.1', build: 5, certificate: '' }));
});

test('changelog rejects malformed or unbounded entries', () => {
  assert.deepEqual(validateChangelog(changelog), changelog);
  for (const invalid of [[], null, [{ type: 'html', text: 'hello' }], [{ type: 'fixed', text: '' }], [{ type: 'added', text: 'x'.repeat(501) }]]) assert.throws(() => validateChangelog(invalid));
});

test('publication uploads once, creates draft, verifies fetched binary then publishes last', async () => {
  const store = fakeStore();
  const result = await publishRelease({ artifact, changelog, store });
  assert.equal(result.state, 'published');
  assert.deepEqual(store.calls, ['upload', 'draft', 'download', 'publish']);
});

for (const fail of ['upload', 'draft', 'download', 'hash', 'size', 'publish']) {
  test(`publication fails closed after ${fail} failure`, async () => {
    const store = fakeStore(fail);
    await assert.rejects(publishRelease({ artifact, changelog, store }));
    if (fail !== 'publish') assert.ok(!store.calls.includes('publish'));
  });
}

test('build numbers must exceed even draft and withdrawn builds', async () => {
  const store = fakeStore(); store.highest = 6;
  await assert.rejects(publishRelease({ artifact, changelog, store }), /higher/);
  assert.deepEqual(store.calls, []);
});

test('Storage adapter disables overwrites and does not expose provider secrets in errors', async () => {
  let options;
  const store = createReleaseStore({ storage: { from(name) {
    assert.equal(name, 'app-releases');
    return { upload: async (_path, _bytes, uploadOptions) => {
      options = uploadOptions;
      return { data: null, error: { message: 'secret-key-signed-url' } };
    } };
  } } });
  await assert.rejects(store.upload('immutable-path', bytes), error => {
    assert.equal(error.message.includes('secret-key'), false);
    return true;
  });
  assert.equal(options.upsert, false);
  assert.equal(options.contentType, 'application/vnd.android.package-archive');
});

test('a matching draft can be verified and resumed without overwriting artifact', async () => {
  const store = fakeStore();
  let draft;
  store.insertDraft = async row => { draft = { ...row, id: 'release-id' }; return draft; };
  await publishRelease({ artifact, changelog, store });
  store.existing = draft; store.highest = 5; store.calls.length = 0;
  await publishRelease({ artifact, changelog, store });
  assert.deepEqual(store.calls, ['download', 'publish']);
  store.existing = { ...draft, sha256: '00'.repeat(32) }; store.calls.length = 0;
  await assert.rejects(publishRelease({ artifact, changelog, store }), /match/);
  assert.deepEqual(store.calls, []);
  store.existing = { ...draft, state: 'withdrawn' };
  await assert.rejects(publishRelease({ artifact, changelog, store }), /match/);
});
