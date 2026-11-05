import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

const bucket = 'app-releases';
const tuple = { platform: 'android', channel: 'beta', distribution: 'direct_apk' };
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const versionPattern = /^\d+\.\d+\.\d+$/;

export function validateChangelog(entries) {
  if (!Array.isArray(entries) || entries.length < 1 || entries.length > 30 || entries.some(entry =>
    !entry || !['added', 'changed', 'fixed'].includes(entry.type) || typeof entry.text !== 'string' ||
    !entry.text.trim() || entry.text.length > 500 || Object.keys(entry).some(key => !['type', 'text'].includes(key)))) {
    throw Error('Changelog must contain 1–30 plain-text added, changed or fixed entries (1–500 characters).');
  }
  return entries;
}

/** Only supports the universal APK produced by the documented Flutter build. */
export function parseApkIdentity(badging, certificates, expected) {
  const pkg = badging.match(/^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'/m);
  const sdk = badging.match(/^sdkVersion:'(\d+)'/m);
  const digests = [...certificates.matchAll(/^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})\s*$/gm)];
  const pinned = (expected.certificate ?? '').replace(/:/g, '').toLowerCase();
  const native = badging.match(/^native-code: (.+)$/m)?.[1] ?? '';
  if (!pkg || pkg[1] !== 'com.noted.app' || pkg[3] !== expected.version || !versionPattern.test(pkg[3]) || pkg[3].length > 40 ||
      Number(pkg[2]) !== expected.build || !Number.isInteger(expected.build) || expected.build < 1 || expected.build > 2100000000 ||
      !sdk || Number(sdk[1]) < 24 || Number(sdk[1]) > 1000 || /^maxSdkVersion:/m.test(badging) ||
      !['armeabi-v7a', 'arm64-v8a', 'x86_64'].every(abi => native.includes(`'${abi}'`)) ||
      !/^[a-f0-9]{64}$/.test(pinned) || digests.length !== 1 || digests[0][1].toLowerCase() !== pinned ||
      /Android Debug/i.test(certificates) || /android\.permission\.REQUEST_INSTALL_PACKAGES/.test(badging)) {
    throw Error('APK identity, universal ABI coverage, SDK or release signing certificate does not match the expected release.');
  }
  return { version: pkg[3], build_number: Number(pkg[2]), min_sdk: Number(sdk[1]) };
}

function run(executable, args) {
  // No shell, command interpolation, signing passwords, or provider responses in output.
  const result = spawnSync(executable, args, { encoding: 'utf8', windowsHide: true, shell: false, maxBuffer: 8 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw Error('Android SDK artifact verification failed. Check the SDK tools and APK locally.');
  return result.stdout;
}

export async function inspectApk({ apk, version, build, buildTools, certificate, maxBytes = 50 * 1024 * 1024 }, runTool = run) {
  if (!apk || !buildTools) throw Error('Provide --apk and --build-tools paths.');
  if (!Number.isInteger(maxBytes) || maxBytes < 1 || maxBytes > 536870912) throw Error('maxBytes must be an integer from 1 through 536870912.');
  const apkPath = path.resolve(apk);
  const info = await fs.stat(apkPath);
  if (!info.isFile() || info.size < 1 || info.size > maxBytes) throw Error('APK exceeds the configured size budget or is not a nonempty file.');
  const bytes = await fs.readFile(apkPath);
  if (bytes.length !== info.size || !bytes.length || bytes.length > maxBytes) throw Error('APK changed size while reading or exceeds the configured size budget.');
  // A concurrent Flutter build can replace its output path. Both SDK checks must
  // inspect a private snapshot of the exact buffer that publication will upload.
  const directory = await fs.mkdtemp(path.join(path.resolve(os.tmpdir()), 'noted-release-'));
  const snapshot = path.join(directory, 'verified.apk');
  try {
    await fs.writeFile(snapshot, bytes, { flag: 'wx', mode: 0o600 });
    const badging = runTool(path.join(buildTools, process.platform === 'win32' ? 'aapt.exe' : 'aapt'), ['dump', 'badging', snapshot]);
    // Java invokes the SDK jar directly on Windows; apksigner.bat would need a shell.
    const certificates = runTool('java', ['-jar', path.join(buildTools, 'lib', 'apksigner.jar'), 'verify', '--verbose', '--print-certs', '-Werr', snapshot]);
    const identity = parseApkIdentity(badging, certificates, { version, build, certificate });
    return { ...identity, size_bytes: bytes.length, sha256: sha256(bytes), bytes };
  } finally {
    // Only remove our own file and now-empty directory; never delete recursively.
    await fs.rm(snapshot, { force: true });
    await fs.rmdir(directory);
  }
}

export async function publishRelease({ artifact, changelog, store }) {
  validateChangelog(changelog);
  const { version, build_number: build, min_sdk, size_bytes, sha256: hash, bytes } = artifact;
  if (!versionPattern.test(version) || version.length > 40 || !Number.isInteger(build) || build < 1 || build > 2100000000 ||
      !Number.isInteger(min_sdk) || min_sdk < 24 || min_sdk > 1000 || !bytes?.length ||
      size_bytes !== bytes.length || sha256(bytes) !== hash) throw Error('Invalid verified artifact.');
  const row = {
    ...tuple, version, build_number: build, min_sdk, size_bytes, sha256: hash, changelog,
    state: 'draft', object_path: `android/beta/${version}/${build}/noted-${version}-build-${build}.apk`,
  };
  const existing = await store.findBuild(build);
  const highest = await store.highestBuild();
  if (highest > build || (!existing && highest >= build)) throw Error('Choose a build number higher than every reserved release build.');
  let draft;
  if (existing) {
    if (Object.entries(row).some(([key, value]) => !isDeepStrictEqual(existing[key], value))) {
      throw Error('Existing release does not match this draft; use a new build number.');
    }
    draft = existing;
  } else {
    // Never overwrite. If upload/insert is interrupted, leave the object for inspection.
    await store.upload(row.object_path, bytes);
    draft = await store.insertDraft(row);
  }
  const uploaded = await store.download(row.object_path);
  if (uploaded.length !== size_bytes || sha256(uploaded) !== hash) throw Error('Uploaded artifact size or SHA-256 does not match; draft remains unpublished.');
  // The server atomically checks draft identity, storage presence, and monotonic build.
  return store.publish(draft.id, size_bytes, hash);
}

export function createReleaseStore(client) {
  async function requireResult(request, operation) {
    const { data, error } = await request;
    if (error) throw Error(`Release ${operation} failed; no successful publication is confirmed.`);
    return data;
  }
  const matching = query => query.eq('platform', tuple.platform).eq('channel', tuple.channel).eq('distribution', tuple.distribution);
  return {
    findBuild: build => requireResult(matching(client.from('app_releases').select('*')).eq('build_number', build).maybeSingle(), 'lookup'),
    async highestBuild() {
      const rows = await requireResult(matching(client.from('app_releases').select('build_number')).order('build_number', { ascending: false }).limit(1), 'lookup');
      return rows?.[0]?.build_number ?? 0;
    },
    upload: (objectPath, bytes) => requireResult(client.storage.from(bucket).upload(objectPath, bytes, {
      contentType: 'application/vnd.android.package-archive', upsert: false, cacheControl: '3600',
    }), 'upload'),
    insertDraft: row => requireResult(client.from('app_releases').insert(row).select('*').single(), 'draft creation'),
    async download(objectPath) {
      const blob = await requireResult(client.storage.from(bucket).download(objectPath), 'artifact readback');
      return Buffer.from(await blob.arrayBuffer());
    },
    publish: (id, size, hash) => requireResult(client.rpc('publish_app_release', { p_release_id: id, p_size_bytes: size, p_sha256: hash }), 'publication'),
    withdraw: id => requireResult(client.from('app_releases').update({ state: 'withdrawn' }).eq('id', id).eq('state', 'published').select('id,state').single(), 'withdrawal'),
  };
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const values = {};
  const allowed = new Set(['apk', 'version', 'build', 'changelog', 'build-tools', 'release-id']);
  for (let i = 0; i < rest.length; i += 2) {
    const key = rest[i].replace(/^--/, '');
    if (!rest[i].startsWith('--') || !allowed.has(key) || !rest[i + 1] || values[key]) throw Error('Invalid release command arguments.');
    values[key] = rest[i + 1];
  }
  if (!['verify', 'publish', 'withdraw'].includes(command)) throw Error('Usage: node tools/releases/release.mjs verify|publish|withdraw [options]. See docs/beta-releases.md.');
  return { command, values };
}

async function main() {
  const { command, values } = parseArgs(process.argv.slice(2));
  let artifact;
  if (command !== 'withdraw') {
    artifact = await inspectApk({ apk: values.apk, version: values.version, build: Number(values.build), buildTools: values['build-tools'], certificate: process.env.NOTED_SIGNING_CERT_SHA256, maxBytes: Number(process.env.NOTED_MAX_APK_BYTES ?? 52428800) });
    const { bytes: _, ...summary } = artifact;
    console.log(JSON.stringify(summary, null, 2));
    if (command === 'verify') return;
  }
  let changelog;
  if (command === 'publish') {
    if (!values.changelog) throw Error('Provide --changelog path.');
    changelog = validateChangelog(JSON.parse(await fs.readFile(values.changelog, 'utf8')));
  } else if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(values['release-id'] ?? '')) {
    throw Error('Provide a valid --release-id UUID.');
  }
  const url = new URL(process.env.SUPABASE_URL ?? '');
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') throw Error('SUPABASE_URL must be an HTTPS origin.');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key?.trim()) throw Error('SUPABASE_SERVICE_ROLE_KEY is required only for publication/withdrawal.');
  const require = createRequire(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../migration/package.json'));
  const { createClient } = require('@supabase/supabase-js');
  const store = createReleaseStore(createClient(url.origin, key, { auth: { persistSession: false, autoRefreshToken: false } }));
  const result = command === 'publish' ? await publishRelease({ artifact, changelog, store }) : await store.withdraw(values['release-id']);
  // Do not log raw Supabase responses, environment values, or signed URLs.
  console.log(command === 'publish' ? 'Release published after artifact verification.' : 'Release withdrawn. Previously issued downloads remain valid until expiry.');
  if (result?.id) console.log(`Release ID: ${result.id}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(() => {
    // Provider exceptions can contain credentials or URLs. Keep CLI failure output bounded.
    console.error('Release command failed. No successful publication is confirmed. Check arguments, SDK tools, signing identity and private backend configuration; inspect draft state before retrying.');
    process.exitCode = 1;
  });
}
