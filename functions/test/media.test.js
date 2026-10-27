'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {canDuplicate, draftForCopy, copyNoteMedia} = require('../media');
function fakeBucket(fail = false) {
  const files = new Map([['users/owner/notes/original/photo.jpg', {bytes: 'original pixels'}]]);
  return {name: 'test-bucket', files, file(path) { return {name: path,
    async copy(target) { if (!files.has(path)) throw new Error('missing source'); files.set(target.name, {...files.get(path)}); },
    async setMetadata(metadata) { if(fail) throw new Error('metadata failure'); files.get(path).metadata = metadata; },
    async delete() { files.delete(path); },
  }; }};
}
test('duplicate authorization excludes strangers, pending copies and deleted live membership', () => {
  assert.equal(canDuplicate({userId:'owner'},'owner'),true);
  assert.equal(canDuplicate({userId:'owner',liveMemberIds:['viewer']},'viewer'),true);
  assert.equal(canDuplicate({userId:'owner',pendingSharedWithUserIds:['viewer']},'viewer'),false);
  assert.equal(canDuplicate({userId:'owner',liveMemberIds:['viewer'],deletedAt:1},'viewer'),false);
  assert.equal(canDuplicate({userId:'owner',deletedAt:1},'owner'),true);
});
test('draft projection preserves unsaved content without accepting ownership or role changes', () => {
  const value=draftForCopy({userId:'owner',title:'Saved',content:'Old',liveRoles:{a:'edit'}},{userId:'attacker',title:'Recovered',content:'Unsaved',liveRoles:{a:'view'}});
  assert.equal(value.userId,'owner');assert.equal(value.content,'Unsaved');assert.equal(value.liveRoles.a,'edit');
  assert.throws(()=>draftForCopy({}, {color:'invalid'}));
});
test('duplicate media remains independent after original media deletion and rewrites inline links', async () => {
  const bucket=fakeBucket();let n=0;
  const result=await copyNoteMedia({attachments:[{path:'users/owner/notes/original/photo.jpg',url:'https://old',name:'photo.jpg'}],sourceNoteId:'original',targetUid:'viewer',targetNoteId:'copy',bucket,uuid:()=>`id${++n}`});
  assert.equal(result.attachments[0].path,'users/viewer/notes/copy/id1_photo.jpg');
  await bucket.file('users/owner/notes/original/photo.jpg').delete();
  assert.equal(bucket.files.get(result.attachments[0].path).bytes,'original pixels');
  assert.match(result.rewriteContent('image https://old'),/test-bucket/);
  assert.equal(result.attachments[0].url.includes('token=id2'),true);
});
test('copy rejects foreign-note attachment paths and cleans partial uploads', async () => {
  const bucket=fakeBucket();let n=0;
  await assert.rejects(copyNoteMedia({attachments:[{path:'users/owner/notes/original/photo.jpg'},{path:'users/owner/notes/secret/photo.jpg'}],sourceNoteId:'original',targetUid:'viewer',targetNoteId:'copy',bucket,uuid:()=>`id${++n}`}),/source note/);
  assert.deepEqual([...bucket.files.keys()],['users/owner/notes/original/photo.jpg']);
  const broken=fakeBucket(true);
  await assert.rejects(copyNoteMedia({attachments:[{path:'users/owner/notes/original/photo.jpg'}],sourceNoteId:'original',targetUid:'viewer',targetNoteId:'copy',bucket:broken}),/metadata failure/);
  assert.deepEqual([...broken.files.keys()],['users/owner/notes/original/photo.jpg']);
});
