'use strict';
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const run = process.env.FIRESTORE_EMULATOR_HOST ? test : test.skip;
run('Firestore enforces collaboration, invitation, connection and preference boundaries', async () => {
  const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
  const {doc, setDoc, getDoc, getDocs, collection, query, where, updateDoc, Timestamp} = require('firebase/firestore');
  const env = await initializeTestEnvironment({projectId: 'demo-noted', firestore: {rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  try {
    const now = Timestamp.now();
    const note = {noteId: 'n', userId: 'owner', ownerName: 'Owner', ownerEmail: '', title: 'Shared', content: 'Draft', category: 'Work',
      color: 'blue', isFavorite: false, liveMemberIds: ['editor', 'viewer'], liveRoles: {editor: 'edit', viewer: 'view'},
      sharedWithUserIds: [], pendingSharedWithUserIds: ['recipient', 'other'], revision: 0, deletedAt: null, createdAt: now, updatedAt: now};
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      await setDoc(doc(db, 'notes/n'), note);
      await setDoc(doc(db, 'notes/deleted-shared'), {...note, noteId: 'deleted-shared', deletedAt: now});
      await setDoc(doc(db, 'connectionRequests/c'), {fromUserId: 'owner', toUserId: 'recipient', status: 'pending', updatedAt: now});
    });
    const as = uid => env.authenticatedContext(uid).firestore();
    await assertFails(getDocs(query(collection(as('viewer'),'notes'),where('liveMemberIds','array-contains','viewer'))));
    await assertFails(getDoc(doc(as('viewer'), 'notes/deleted-shared')));
    const liveNotes = await assertSucceeds(getDocs(query(collection(as('viewer'),'notes'),where('liveMemberIds','array-contains','viewer'),where('deletedAt','==',null))));
    const pendingNotes = await assertSucceeds(getDocs(query(collection(as('recipient'),'notes'),where('pendingSharedWithUserIds','array-contains','recipient'),where('deletedAt','==',null))));
    require('node:assert/strict').deepEqual(liveNotes.docs.map(doc => doc.id), ['n']);
    require('node:assert/strict').deepEqual(pendingNotes.docs.map(doc => doc.id), ['n']);
    await assertSucceeds(getDoc(doc(as('editor'), 'notes/n')));
    await assertSucceeds(getDoc(doc(as('viewer'), 'notes/n')));
    await assertSucceeds(setDoc(doc(as('viewer'), 'users/viewer/favorites/n'), {noteId: 'n'}));
    await assertFails(setDoc(doc(as('stranger'), 'users/stranger/favorites/n'), {noteId: 'n'}));
    await assertFails(getDoc(doc(as('owner'), 'users/viewer/favorites/n')));
    await assertFails(updateDoc(doc(as('editor'), 'notes/n'), {isFavorite: true, revision: 1}));
    await assertFails(getDoc(doc(as('stranger'), 'notes/n')));
    await assertFails(updateDoc(doc(as('viewer'), 'notes/n'), {content: 'overwrite', revision: 1}));
    await assertSucceeds(updateDoc(doc(as('editor'), 'notes/n'), {content: 'valid', revision: 1}));
    await assertFails(updateDoc(doc(as('editor'), 'notes/n'), {content: 'stale', revision: 1}));
    await assertFails(updateDoc(doc(as('editor'), 'notes/n'), {userId: 'editor', revision: 2}));
    await assertFails(updateDoc(doc(as('owner'), 'notes/n'), {liveRoles: {editor: 'view'}}));
    await assertFails(updateDoc(doc(as('owner'), 'notes/n'), {pendingSharedWithUserIds: ['stranger']}));
    await assertFails(updateDoc(doc(as('recipient'), 'notes/n'), {pendingSharedWithUserIds: []}));
    await assertSucceeds(updateDoc(doc(as('recipient'), 'notes/n'), {pendingSharedWithUserIds: ['other']}));
    await assertFails(updateDoc(doc(as('owner'), 'connectionRequests/c'), {status: 'accepted'}));
    await assertSucceeds(updateDoc(doc(as('recipient'), 'connectionRequests/c'), {status: 'accepted'}));
    await assertFails(updateDoc(doc(as('recipient'), 'connectionRequests/c'), {fromUserId: 'stranger'}));
    await assertSucceeds(setDoc(doc(as('owner'), 'users/owner/settings/preferences'), {theme: 'dark'}));
    await assertFails(getDoc(doc(as('stranger'), 'users/owner/settings/preferences')));
    await assertSucceeds(updateDoc(doc(as('owner'), 'notes/n'), {deletedAt: now}));
    await assertFails(getDoc(doc(as('viewer'), 'notes/n')));
    await assertSucceeds(getDoc(doc(as('owner'), 'notes/n')));
    await assertFails(updateDoc(doc(as('editor'), 'notes/n'), {deletedAt: null}));
    await assertSucceeds(updateDoc(doc(as('owner'), 'notes/n'), {deletedAt: null}));
  } finally { await env.cleanup(); }
});
const runStorage = process.env.FIREBASE_STORAGE_EMULATOR_HOST && process.env.FIRESTORE_EMULATOR_HOST ? test : test.skip;
runStorage('Storage restricts note uploads to editors and private media reads to members', async () => {
  const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
  const {doc, setDoc} = require('firebase/firestore');
  const {ref, uploadBytes, getBytes} = require('firebase/storage');
  const env = await initializeTestEnvironment({projectId: 'demo-noted',
    firestore: {rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8')},
    storage: {rules: readFileSync(resolve(__dirname, '../../storage.rules'), 'utf8')},
  });
  try {
    await env.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), 'notes/storage-note'), {userId: 'owner', liveMemberIds: ['editor', 'viewer'], liveRoles: {editor: 'edit', viewer: 'view'}});
    });
    const bytes = new Uint8Array([137, 80, 78, 71]);
    const path = 'users/editor/notes/storage-note/image.png';
    await assertSucceeds(uploadBytes(ref(env.authenticatedContext('editor').storage(), path), bytes, {contentType: 'image/png'}));
    await assertSucceeds(getBytes(ref(env.authenticatedContext('viewer').storage(), path)));
    await assertFails(uploadBytes(ref(env.authenticatedContext('viewer').storage(), 'users/viewer/notes/storage-note/image.png'), bytes, {contentType: 'image/png'}));
    await assertFails(getBytes(ref(env.authenticatedContext('stranger').storage(), path)));
    await assertFails(uploadBytes(ref(env.authenticatedContext('editor').storage(), 'users/editor/notes/storage-note/script.html'), bytes, {contentType: 'text/html'}));
  } finally { await env.cleanup(); }
});
