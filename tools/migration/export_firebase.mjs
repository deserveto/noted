import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inferAllowedMimeType } from './id_mapping.mjs';

export const REQUIRED_IAM_ROLES = [
  'Firebase Authentication Viewer',
  'Cloud Datastore Viewer',
  'Storage Object Viewer',
];

export function buildBlockerReport(projectId, details = null) {
  return {
    status: 'BLOCKED',
    error: 'Missing or unauthorized Firebase Admin credentials',
    requirement:
      'Requirement 10 compliance: NEVER fabricate export data or mutate/delete Firebase entities',
    project: projectId || 'superheromood-54691',
    requiredIamRoles: REQUIRED_IAM_ROLES,
    actionRequired:
      'Provide a valid Google Cloud / Firebase service account key JSON via --service-account <path> or the GOOGLE_APPLICATION_CREDENTIALS environment variable. Ensure the service account has the required read-only IAM roles: Firebase Authentication Viewer (users), Cloud Datastore Viewer (Firestore), and Storage Object Viewer (Storage blobs).',
    ...(details ? { details } : {}),
  };
}

export function printBlockerBanner(report) {
  const line = '='.repeat(80);
  console.error(line);
  console.error('FIREBASE EXPORT BLOCKED: Missing or Unauthorized Credentials');
  console.error(line);
  console.error(
    'Requirement 10: Export tooling will NEVER fabricate synthetic or mock data.\n' +
      `Target Firebase Project: ${report.project}\n\n` +
      'To export real Firebase data, provide credentials with the following IAM roles:\n' +
      report.requiredIamRoles.map((r) => `  - ${r}`).join('\n') +
      '\n\n' +
      report.actionRequired +
      '\n\nStructured Blocker Report:\n' +
      JSON.stringify(report, null, 2),
  );
  console.error(line);
}

export function parseArgs(argv = process.argv.slice(2)) {
  const args = {
    out: './exports/latest',
    project: 'superheromood-54691',
    serviceAccount: process.env.GOOGLE_APPLICATION_CREDENTIALS || null,
    includeMedia: true,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--out' && i + 1 < argv.length) {
      args.out = argv[++i];
    } else if (arg === '--project' && i + 1 < argv.length) {
      args.project = argv[++i];
    } else if (arg === '--service-account' && i + 1 < argv.length) {
      args.serviceAccount = argv[++i];
    } else if (arg === '--include-media') {
      const next = argv[i + 1];
      if (next === 'false' || next === '0') {
        args.includeMedia = false;
        i++;
      } else {
        args.includeMedia = true;
      }
    } else if (arg === '--no-include-media') {
      args.includeMedia = false;
    }
  }
  return args;
}

export async function computeFileSha256(filePath) {
  const data = await fs.readFile(filePath);
  return crypto.createHash('sha256').update(data).digest('hex');
}

/**
 * Loads an exported Firebase bundle directory into a unified in-memory bundle structure.
 */
export async function loadBundleFromDir(dirPath) {
  const manifestPath = path.join(dirPath, 'manifest.json');
  const manifestRaw = await fs.readFile(manifestPath, 'utf8');
  const manifest = JSON.parse(manifestRaw);

  if (!manifest.checksums || typeof manifest.checksums !== 'object') throw new Error('Bundle manifest missing checksums');
  const required = ['users.json', ...['users','notes','connection_requests','user_settings','user_favorites','user_invitations','notifications','ai_chats','ai_messages','ai_requests'].map(n => `firestore/${n}.json`)];
  for (const rel of required) {
    if (!/^[a-f0-9]{64}$/i.test(manifest.checksums[rel] || '')) throw new Error(`Bundle missing checksum: ${rel}`);
  }
  for (const [rel, expected] of Object.entries(manifest.checksums)) {
    if (path.isAbsolute(rel) || rel.split(/[\\/]/).includes('..')) throw new Error('Invalid bundle path');
    if (!/^[a-f0-9]{64}$/i.test(expected) || await computeFileSha256(path.join(dirPath, rel)) !== expected) throw new Error(`Bundle checksum mismatch: ${rel}`);
  }
  for (const item of manifest.mediaManifest || []) {
    if (!manifest.checksums[`media/${item.sourcePath}`]) throw new Error(`Bundle missing media checksum: ${item.sourcePath}`);
  }

  const usersPath = path.join(dirPath, 'users.json');
  const usersRaw = await fs.readFile(usersPath, 'utf8');
  const usersFile = JSON.parse(usersRaw);
  if (!Array.isArray(usersFile.users)) throw new Error('Invalid bundle auth users');

  const firestoreDir = path.join(dirPath, 'firestore');
  const firestoreFiles = [
    'users.json',
    'notes.json',
    'connection_requests.json',
    'user_settings.json',
    'user_favorites.json',
    'user_invitations.json',
    'notifications.json',
    'ai_chats.json',
    'ai_messages.json',
    'ai_requests.json',
  ];

  const firestore = {};
  for (const f of firestoreFiles) {
    const p = path.join(firestoreDir, f);
    const key = path.basename(f, '.json');
    const raw = await fs.readFile(p, 'utf8');
    firestore[key] = JSON.parse(raw);
    if (!Array.isArray(firestore[key])) throw new Error(`Invalid bundle dataset: ${f}`);
  }

  // Media files under media/
  const mediaDir = path.join(dirPath, 'media');
  const mediaMetaMap = new Map(
    (Array.isArray(manifest?.mediaManifest) ? manifest.mediaManifest : []).map((m) => [
      m.sourcePath,
      m.contentType,
    ]),
  );
  const media = [];
  async function scanMedia(sub) {
    try {
      const entries = await fs.readdir(sub, { withFileTypes: true });
      for (const entry of entries) {
        const full = path.join(sub, entry.name);
        if (entry.isDirectory()) {
          await scanMedia(full);
        } else if (entry.isFile()) {
          const rel = path.relative(mediaDir, full).replace(/\\/g, '/');
          if (!manifest.checksums[`media/${rel}`]) throw new Error(`Unlisted media file: ${rel}`);
          const data = await fs.readFile(full);
          const bucket = rel.includes('/notes/') ? 'note-media' : 'avatars';
          const contentType = inferAllowedMimeType(
            rel,
            mediaMetaMap.get(rel) || '',
            bucket,
          );
          media.push({
            sourcePath: rel,
            data,
            contentType,
            size: data.length,
            md5: crypto.createHash('md5').update(data).digest('hex'),
          });
        }
      }
    } catch (err) {
      if (err.code !== 'ENOENT' || (manifest.mediaManifest || []).length) throw err;
    }
  }
  await scanMedia(mediaDir);

  const datasetCounts = { authUsers: usersFile.users.length, users: firestore.users.length, notes: firestore.notes.length, connectionRequests: firestore.connection_requests.length, userSettings: firestore.user_settings.length, userFavorites: firestore.user_favorites.length, userInvitations: firestore.user_invitations.length, notifications: firestore.notifications.length, aiChats: firestore.ai_chats.length, aiMessages: firestore.ai_messages.length, aiRequests: firestore.ai_requests.length, media: media.length };
  for (const [key, count] of Object.entries(datasetCounts)) {
    if (manifest.counts?.[key] !== count) throw new Error(`Bundle count mismatch: ${key}`);
  }
  return {
    manifest,
    authUsers: usersFile.users || [],
    auth: usersFile,
    firestore: {
      users: firestore.users || [],
      notes: firestore.notes || [],
      connectionRequests: firestore.connection_requests || [],
      userSettings: firestore.user_settings || [],
      userFavorites: firestore.user_favorites || [],
      userInvitations: firestore.user_invitations || [],
      notifications: firestore.notifications || [],
      aiChats: firestore.ai_chats || [],
      aiMessages: firestore.ai_messages || [],
      aiRequests: firestore.ai_requests || [],
    },
    media,
  };
}

/**
 * Programmatically exports Firebase data using an authenticated Firebase Admin App.
 */
export async function exportFirebaseBundle(adminApp, options = {}) {
  const projectId = options.projectId || 'superheromood-54691';
  if (!adminApp) {
    const err = new Error(
      'Firebase Admin credentials missing or unauthorized. Cannot fabricate export data (Requirement 10).',
    );
    err.blockerReport = buildBlockerReport(projectId, 'adminApp instance is null or unconfigured');
    throw err;
  }

  const onProgress = typeof options.onProgress === 'function' ? options.onProgress : () => {};

  // 1. Export Auth Users
  onProgress({ stage: 'auth', message: 'Listing Firebase Auth users...' });
  const authUsers = [];
  try {
    let pageToken;
    do {
      const listResult = await adminApp.auth().listUsers(1000, pageToken);
      for (const u of listResult.users || []) {
        authUsers.push({
          uid: u.uid,
          email: u.email || '',
          displayName: u.displayName || '',
          emailVerified: Boolean(u.emailVerified),
          disabled: Boolean(u.disabled),
          metadata: {
            creationTime: u.metadata?.creationTime,
            lastSignInTime: u.metadata?.lastSignInTime,
          },
          customClaims: u.customClaims || {},
          providerData: u.providerData || [],
          passwordHash: u.passwordHash || null,
          passwordSalt: u.passwordSalt || null,
        });
      }
      pageToken = listResult.pageToken;
    } while (pageToken);
  } catch (err) {
    const wrapped = new Error(
      `Firebase Auth export failed: ${err.message}. Ensure service account has "Firebase Authentication Viewer" role.`,
    );
    wrapped.blockerReport = buildBlockerReport(projectId, err.message);
    throw wrapped;
  }

  // 2. Export Firestore Collections
  onProgress({ stage: 'firestore', message: 'Exporting Firestore collections...' });
  const db = adminApp.firestore();
  const users = [];
  const userSettings = [];
  const userFavorites = [];
  const userInvitations = [];
  const notifications = [];
  const aiChats = [];
  const aiMessages = [];
  const aiRequests = [];

  try {
    const usersCol = db.collection('users');
    let userDocs = [];
    if (typeof usersCol.listDocuments === 'function') {
      const refs = await usersCol.listDocuments();
      for (const ref of refs || []) {
        const snap = await ref.get();
        userDocs.push({
          id: ref.id,
          exists: snap ? snap.exists !== false : false,
          data: () => (snap && typeof snap.data === 'function' ? snap.data() || {} : {}),
          ref,
        });
      }
    } else {
      const usersSnap = await usersCol.get();
      userDocs = (usersSnap.docs || []).map((doc) => ({
        id: doc.id,
        exists: true,
        data: () => doc.data() || {},
        ref: doc.ref,
      }));
    }

    for (const doc of userDocs) {
      if (doc.exists) {
        users.push({ id: doc.id, ...doc.data() });
      } else {
        users.push({ id: doc.id });
      }

      // Subcollections
      try {
        const settingsSnap = await doc.ref.collection('settings').doc('preferences').get();
        if (settingsSnap && settingsSnap.exists) {
          userSettings.push({ userId: doc.id, ...settingsSnap.data() });
        }
      } catch (err) { throw err; }

      try {
        const favsSnap = await doc.ref.collection('favorites').get();
        for (const f of favsSnap.docs || []) {
          userFavorites.push({ userId: doc.id, noteId: f.id, ...f.data() });
        }
      } catch (err) { throw err; }

      try {
        const invsSnap = await doc.ref.collection('invitations').get();
        for (const i of invsSnap.docs || []) {
          userInvitations.push({ userId: doc.id, emailHash: i.id, ...i.data() });
        }
      } catch (err) { throw err; }

      try {
        const notifsSnap = await doc.ref.collection('notifications').get();
        for (const n of notifsSnap.docs || []) {
          notifications.push({ id: n.id, userId: doc.id, ...n.data() });
        }
      } catch (err) { throw err; }

      try {
        const chatsSnap = await doc.ref.collection('chats').get();
        for (const c of chatsSnap.docs || []) {
          aiChats.push({ userId: doc.id, chatId: c.id, ...c.data() });
          try {
            const msgsSnap = await c.ref.collection('messages').get();
            for (const m of msgsSnap.docs || []) {
              aiMessages.push({ id: m.id, userId: doc.id, chatId: c.id, ...m.data() });
            }
          } catch (err) { throw err; }
        }
      } catch (err) { throw err; }

      try {
        const reqsSnap = await doc.ref.collection('aiRequests').get();
        for (const r of reqsSnap.docs || []) {
          aiRequests.push({ userId: doc.id, requestId: r.id, ...r.data() });
        }
      } catch (err) { throw err; }
    }
  } catch (err) {
    const wrapped = new Error(
      `Firestore export failed: ${err.message}. Ensure service account has "Cloud Datastore Viewer" role.`,
    );
    wrapped.blockerReport = buildBlockerReport(projectId, err.message);
    throw wrapped;
  }

  const notes = [];
  try {
    const notesSnap = await db.collection('notes').get();
    for (const doc of notesSnap.docs || []) {
      notes.push({ id: doc.id, ...doc.data() });
    }
  } catch (err) {
    const wrapped = new Error(
      `Firestore notes export failed: ${err.message}. Ensure service account has "Cloud Datastore Viewer" role.`,
    );
    wrapped.blockerReport = buildBlockerReport(projectId, err.message);
    throw wrapped;
  }

  const connectionRequests = [];
  try {
    const connsSnap = await db.collection('connectionRequests').get();
    for (const doc of connsSnap.docs || []) {
      connectionRequests.push({ id: doc.id, ...doc.data() });
    }
  } catch (err) {
    const wrapped = new Error(
      `Firestore connection_requests export failed: ${err.message}. Ensure service account has "Cloud Datastore Viewer" role.`,
    );
    wrapped.blockerReport = buildBlockerReport(projectId, err.message);
    throw wrapped;
  }

  // 3. Storage Blobs
  const media = [];
  if (options.includeMedia !== false) {
    onProgress({ stage: 'storage', message: 'Downloading Storage blobs...' });
    try {
      if (typeof adminApp.storage !== 'function') throw new Error('Firebase Storage client unavailable');
      const bucket = adminApp.storage().bucket();
      if (!bucket || typeof bucket.getFiles !== 'function') throw new Error('Firebase Storage bucket unavailable');
      {
        const [files] = await bucket.getFiles({ prefix: 'users/' });
        for (const file of files || []) {
          const [data] = await file.download();
          const bucketName = file.name.includes('/notes/') ? 'note-media' : 'avatars';
          media.push({
            sourcePath: file.name,
            data,
            contentType: inferAllowedMimeType(
              file.name,
              file.metadata?.contentType || '',
              bucketName,
            ),
            size: data.length,
            md5: crypto.createHash('md5').update(data).digest('hex'),
          });
        }
      }
    } catch (err) {
      const wrapped = new Error(
        `Storage export failed: ${err.message}. Ensure service account has "Storage Object Viewer" role.`,
      );
      wrapped.blockerReport = buildBlockerReport(projectId, err.message);
      throw wrapped;
    }
  }

  const bundle = {
    manifest: {
      version: '1.0.0',
      projectId,
      exportedAt: new Date().toISOString(),
      counts: {
        authUsers: authUsers.length,
        users: users.length,
        notes: notes.length,
        connectionRequests: connectionRequests.length,
        userSettings: userSettings.length,
        userFavorites: userFavorites.length,
        userInvitations: userInvitations.length,
        notifications: notifications.length,
        aiChats: aiChats.length,
        aiMessages: aiMessages.length,
        aiRequests: aiRequests.length,
        media: media.length,
      },
      mediaManifest: media.map((m) => ({
        sourcePath: m.sourcePath,
        contentType: m.contentType,
        size: m.size,
      })),
    },
    auth: {
      exportNotice:
        "Firebase Auth passwords use a modified-scrypt algorithm with project-specific signer key and salt separator. Raw passwords cannot be decrypted and cannot be directly imported into standard bcrypt/Argon2 Supabase Auth without the project's hash signer key. Users will require a Password Reset on first login unless Firebase hash signer parameters are imported.",
      passwordHashAlgorithm: 'firebase-scrypt',
      users: authUsers,
    },
    firestore: {
      users,
      notes,
      connectionRequests,
      userSettings,
      userFavorites,
      userInvitations,
      notifications,
      aiChats,
      aiMessages,
      aiRequests,
    },
    media,
  };

  // 4. Save to Disk if outDir provided
  if (options.outDir) {
    const outDir = path.resolve(options.outDir);
    const firestoreDir = path.join(outDir, 'firestore');
    const mediaDir = path.join(outDir, 'media');

    await fs.mkdir(firestoreDir, { recursive: true });
    if (media.length > 0) {
      await fs.mkdir(mediaDir, { recursive: true });
    }

    const checksums = {};

    async function writeJson(relPath, payload) {
      const fullPath = path.join(outDir, relPath);
      const str = JSON.stringify(payload, null, 2);
      await fs.writeFile(fullPath, str, 'utf8');
      const hash = crypto.createHash('sha256').update(str).digest('hex');
      checksums[relPath.replace(/\\/g, '/')] = hash;
    }

    await writeJson('users.json', bundle.auth);
    await writeJson('firestore/users.json', users);
    await writeJson('firestore/notes.json', notes);
    await writeJson('firestore/connection_requests.json', connectionRequests);
    await writeJson('firestore/user_settings.json', userSettings);
    await writeJson('firestore/user_favorites.json', userFavorites);
    await writeJson('firestore/user_invitations.json', userInvitations);
    await writeJson('firestore/notifications.json', notifications);
    await writeJson('firestore/ai_chats.json', aiChats);
    await writeJson('firestore/ai_messages.json', aiMessages);
    await writeJson('firestore/ai_requests.json', aiRequests);

    for (const item of media) {
      const targetFile = path.join(mediaDir, item.sourcePath);
      await fs.mkdir(path.dirname(targetFile), { recursive: true });
      await fs.writeFile(targetFile, item.data);
      const rel = `media/${item.sourcePath}`.replace(/\\/g, '/');
      checksums[rel] = crypto.createHash('sha256').update(item.data).digest('hex');
    }

    bundle.manifest.checksums = checksums;
    const manifestStr = JSON.stringify(bundle.manifest, null, 2);
    await fs.writeFile(path.join(outDir, 'manifest.json'), manifestStr, 'utf8');
  }

  return bundle;
}

/**
 * CLI execution entrypoint
 */
async function runCli() {
  const args = parseArgs(process.argv.slice(2));

  // Credential verification
  let hasValidCreds = false;
  let serviceAccountJson = null;

  if (args.serviceAccount) {
    try {
      const raw = await fs.readFile(path.resolve(args.serviceAccount), 'utf8');
      serviceAccountJson = JSON.parse(raw);
      hasValidCreds = Boolean(serviceAccountJson.client_email && serviceAccountJson.private_key);
    } catch {
      hasValidCreds = false;
    }
  }

  if (!hasValidCreds) {
    const report = buildBlockerReport(
      args.project,
      args.serviceAccount
        ? `Service account file not found or invalid: ${args.serviceAccount}`
        : 'Neither --service-account nor GOOGLE_APPLICATION_CREDENTIALS was provided.',
    );
    printBlockerBanner(report);
    process.exit(1);
  }

  // If credentials exist, initialize firebase-admin dynamically
  try {
    const adminModule = await import('firebase-admin');
    const admin = adminModule.default;
    const app = admin.initializeApp(
      {
        credential: admin.credential.cert(serviceAccountJson),
        projectId: args.project,
        storageBucket: `${args.project}.appspot.com`,
      },
      `export-${Date.now()}`,
    );

    console.log(`Starting Firebase export for project ${args.project} to ${args.out}...`);
    const bundle = await exportFirebaseBundle(app, {
      outDir: args.out,
      projectId: args.project,
      includeMedia: args.includeMedia,
      onProgress: ({ stage, message }) => console.log(`[${stage}] ${message}`),
    });

    console.log('Export completed successfully!');
    console.log('Manifest summary:');
    console.log(JSON.stringify(bundle.manifest, null, 2));
  } catch (err) {
    const report = buildBlockerReport(args.project, err.message);
    printBlockerBanner(report);
    process.exit(1);
  }
}

const currentFileUrl = import.meta.url;
const executedFileUrl = pathToFileURL(path.resolve(process.argv[1] || '')).href;
if (currentFileUrl === executedFileUrl) {
  runCli().catch((err) => {
    console.error('Fatal CLI error:', err);
    process.exit(1);
  });
}
