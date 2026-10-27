'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {personalizeFavorites, plainContent, documentHtml, canReadNote, scopedNotes, validatedAnswer, exportNotes, emailAllowed} = require('../policy');
const notes = [
  {noteId: 'own', userId: 'u', title: 'Own', content: 'Private', isFavorite: true, category: 'Work'},
  {noteId: 'live', userId: 'v', liveMemberIds: ['u'], liveRoles: {u: 'view'}, category: 'Work'},
  {noteId: 'secret', userId: 'v', pendingSharedWithUserIds: ['u']},
  {noteId: 'trash', userId: 'u', deletedAt: new Date()},
];
test('retrieval excludes private, pending-copy, and deleted notes', () => {
  assert.deepEqual(scopedNotes(notes, 'u').map(n => n.noteId), ['own', 'live']);
  assert.equal(canReadNote(notes[2], 'u'), false);
});
test('explicit scope rejects guessed private IDs instead of silently expanding', () => {
  assert.throws(() => scopedNotes(notes, 'u', {kind: 'notes', ids: ['secret']}), /not permitted/);
  assert.deepEqual(scopedNotes(notes, 'u', {kind: 'notes', ids: ['live']}).map(n => n.noteId), ['live']);
  assert.throws(() => scopedNotes(notes, 'u', {kind: 'unknown'}));
});
test('favorites and category remain inside authorized pool', () => {
  assert.deepEqual(scopedNotes(notes, 'u', {kind: 'fav'}).map(n => n.noteId), ['own']);
  assert.deepEqual(scopedNotes(notes, 'u', {kind: 'cat', cat: 'Work'}).map(n => n.noteId), ['own', 'live']);
});
test('sources must be actual retrieved note IDs and blocks must be valid', () => {
  assert.throws(() => validatedAnswer({blocks: [{t: 'p', x: 'x'}], sources: ['secret']}, ['own']), /source/);
  assert.throws(() => validatedAnswer({blocks: [{t: 'html', x: '<script>'}], sources: []}, ['own']), /block/);
  assert.throws(() => validatedAnswer({blocks: [{t: 'cards', cards: [{q: 'q'}]}], sources: []}, ['own']), /flashcard/);
  assert.deepEqual(validatedAnswer({blocks: [{t: 'p', x: 'Answer'}], sources: ['own', 'own']}, ['own']).sources, ['own']);
});
test('export is a portable projection, excluding sharing/user private fields', () => {
  const output = exportNotes([{...notes[0], createdAt: {toDate: () => new Date('2026-01-01T12:00:00Z')}, ownerEmail: 'private@example.com'}]);
  assert.equal(output[0].createdAt, '2026-01-01T12:00:00.000Z');
  assert.equal(output[0].color, 'blue');
  assert.equal('ownerEmail' in output[0], false);
  assert.doesNotThrow(() => JSON.parse(JSON.stringify(output)));
});
test('notifications respect disabled preference and local quiet hours', () => {
  assert.equal(emailAllowed({nLive: false}, 'nLive'), false);
  assert.equal(emailAllowed({quietHours: true, timezoneOffsetMinutes: 420}, 'nLive', new Date('2026-01-01T16:00:00Z')), false);
  assert.equal(emailAllowed({quietHours: true, timezoneOffsetMinutes: 420}, 'nLive', new Date('2026-01-01T06:00:00Z')), true);
});

test('Quill envelope retrieval uses document text, not JSON attributes', () => {
  const content = JSON.stringify({notedDocument: 1, ops: [{insert: 'Hello', attributes: {bold: true}}, {insert: '\n', attributes: {header: 2}}, {insert: {image: 'https://example.com/image.png'}}, {insert: '\n'}]});
  assert.equal(plainContent(content), 'Hello\n\n');
  assert.match(documentHtml(content), /<h2><strong>Hello<\/strong><\/h2>/);
  assert.match(documentHtml(content), /<img src="https:\/\/example.com\/image.png"/);
  assert.equal(plainContent('Legacy **Markdown**'), 'Legacy **Markdown**');
});
test('HTML export escapes text and ignores unsafe embed/link URLs', () => {
  const content = JSON.stringify({notedDocument: 1, ops: [{insert: '<script>bad</script>', attributes: {link: 'javascript:alert(1)'}}, {insert: {image: 'javascript:alert(1)'}}, {insert: '\n'}]});
  const html = documentHtml(content);
  assert.match(html, /&lt;script&gt;/);
  assert.equal(html.includes('javascript:'), false);
});

test('shared favorites are personal while owner legacy flags remain compatible', () => {
  const personalized = personalizeFavorites(notes, 'u', ['live']);
  assert.deepEqual(scopedNotes(personalized, 'u', {kind: 'fav'}).map(n => n.noteId), ['own', 'live']);
  const other = personalizeFavorites(notes, 'v', []);
  assert.equal(other.find(n => n.noteId === 'own').isFavorite, false);
});

test('quiet hours match the displayed 22:00–07:00 boundaries', () => {
  assert.equal(emailAllowed({quietHours:true},'nLive',new Date('2026-01-01T06:59:00Z')),false);
  assert.equal(emailAllowed({quietHours:true},'nLive',new Date('2026-01-01T07:00:00Z')),true);
  assert.equal(emailAllowed({quietHours:true},'nLive',new Date('2026-01-01T21:59:00Z')),true);
  assert.equal(emailAllowed({quietHours:true},'nLive',new Date('2026-01-01T22:00:00Z')),false);
});

test('legacy note exports preserve supported formatting without executing HTML',()=>{
  const html=documentHtml('### Title\n**Bold** _italic_ <u>underline</u>\n- item\n- next\n- [x] done\n<script>bad</script>');
  assert.match(html,/<h3>Title<\/h3>/);assert.match(html,/<strong>Bold<\/strong>/);assert.match(html,/<em>italic<\/em>/);assert.match(html,/<u>underline<\/u>/);assert.match(html,/<ul><li>item<\/li><li>next<\/li><\/ul>/);assert.match(html,/disabled checked/);assert.equal(html.includes('<script>'),false);
});
