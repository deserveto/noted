'use strict';
const {randomUUID} = require('node:crypto');

function canDuplicate(note, uid) {
  return !!note && (note.userId === uid || (!note.deletedAt && (note.liveMemberIds || []).includes(uid)));
}
function draftForCopy(source, draft = {}) {
  if (!draft || typeof draft !== 'object' || Array.isArray(draft)) throw new Error('Invalid draft.');
  const result = {...source};
  for (const [key, maximum] of [['title', 1000], ['content', 800000], ['category', 200]]) {
    if (draft[key] === undefined) continue;
    if (typeof draft[key] !== 'string' || draft[key].length > maximum) throw new Error(`Invalid draft ${key}.`);
    result[key] = draft[key];
  }
  if (draft.color !== undefined) {
    if (!['blue', 'pink', 'mint', 'yellow', 'peach', 'lav'].includes(draft.color)) throw new Error('Invalid draft color.');
    result.color = draft.color;
  }
  if (draft.attachments !== undefined) {
    if (!Array.isArray(draft.attachments) || draft.attachments.length > 100) throw new Error('Invalid attachments.');
    result.attachments = draft.attachments;
  }
  return result;
}
async function copyNoteMedia({attachments = [], sourceNoteId, targetUid, targetNoteId, bucket, uuid = randomUUID}) {
  const copied = [];
  const paths = [];
  const replacements = new Map();
  const cleanup = async () => {
    await Promise.all(paths.map(path => bucket.file(path).delete({ignoreNotFound: true}).catch(() => {})));
  };
  try {
    for (const attachment of attachments) {
      const parts = typeof attachment?.path === 'string' ? attachment.path.split('/') : [];
      if (parts.length !== 5 || parts[0] !== 'users' || !parts[1] || parts[2] !== 'notes' || parts[3] !== sourceNoteId || !parts[4] || parts.some(part => part === '..' || part === '.')) {
        throw new Error('An attachment does not belong to the source note. Upload it again before copying.');
      }
      const name = typeof attachment.name === 'string' ? attachment.name.replace(/[^a-zA-Z0-9._-]/g, '_') : 'attachment';
      const path = `users/${targetUid}/notes/${targetNoteId}/${uuid()}_${name}`;
      const token = uuid();
      paths.push(path);
      await bucket.file(attachment.path).copy(bucket.file(path));
      await bucket.file(path).setMetadata({metadata: {firebaseStorageDownloadTokens: token}});
      const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
      if (typeof attachment.url === 'string' && attachment.url) replacements.set(attachment.url, url);
      copied.push({...attachment, path, url});
    }
    return {attachments: copied, cleanup, rewriteContent: content => {
      let value = String(content || '');
      for (const [original, replacement] of replacements) value = value.split(original).join(replacement);
      return value;
    }};
  } catch (error) { await cleanup(); throw error; }
}
module.exports = {canDuplicate, draftForCopy, copyNoteMedia};
