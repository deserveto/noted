'use strict';
// Pure policy functions are shared by handlers and unit tests.
function documentOps(content) {
  if (typeof content !== 'string') return null;
  try { const value = JSON.parse(content); return value.notedDocument === 1 && Array.isArray(value.ops) ? value.ops : null; }
  catch { return null; }
}
function plainContent(content) {
  const ops = documentOps(content);
  if (!ops) return String(content || '');
  return ops.map(op => typeof op.insert === 'string' ? op.insert : '').join('');
}
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
function legacyHtml(content) {
  const inline = value => escapeHtml(value).replace(/&lt;u&gt;(.*?)&lt;\/u&gt;/g,'<u>$1</u>').replace(/\*\*(.+?)\*\*/g,'<strong>$1</strong>').replace(/(?:\*|_)([^*_]+?)(?:\*|_)/g,'<em>$1</em>');
  let output='', list=null;
  const close=()=>{if(list){output+=`</${list}>`;list=null;}};
  for(const line of String(content || '').split('\n')) {
    const task=line.match(/^\s*- \[([ xX])\]\s?(.*)$/);
    const bullet=line.match(/^\s*[-*]\s+(.*)$/);
    const numbered=line.match(/^\s*\d+\.\s+(.*)$/);
    if(task){close();output+=`<p><input type="checkbox" disabled${task[1].toLowerCase()==='x'?' checked':''}> ${inline(task[2])}</p>`;continue;}
    if(bullet||numbered){const type=numbered?'ol':'ul';if(list!==type){close();list=type;output+=`<${type}>`;}output+=`<li>${inline((numbered||bullet)[1])}</li>`;continue;}
    close();
    const heading=line.match(/^(#{1,6})\s+(.*)$/), quote=line.match(/^>\s?(.*)$/);
    if(heading)output+=`<h${heading[1].length}>${inline(heading[2])}</h${heading[1].length}>`;
    else if(quote)output+=`<blockquote>${inline(quote[1])}</blockquote>`;
    else if(line.trim())output+=`<p>${inline(line)}</p>`;
  }
  close();return output;
}
function documentHtml(content) {
  const ops = documentOps(content);
  if (!ops) return legacyHtml(content);
  let output = ''; let line = '';
  for (const op of ops) {
    const attrs = op.attributes || {};
    if (typeof op.insert !== 'string') {
      const image = op.insert?.image;
      if (typeof image === 'string' && /^https:\/\//.test(image)) line += `<img src="${escapeHtml(image)}" alt="Note image">`;
      continue;
    }
    const parts = op.insert.split('\n');
    for (let i = 0; i < parts.length; i++) {
      let inline = escapeHtml(parts[i]);
      if (attrs.bold) inline = `<strong>${inline}</strong>`;
      if (attrs.italic) inline = `<em>${inline}</em>`;
      if (attrs.underline) inline = `<u>${inline}</u>`;
      if (attrs.strike) inline = `<s>${inline}</s>`;
      if (typeof attrs.background==='string' && /^#[0-9a-f]{6}$/i.test(attrs.background)) inline=`<mark style="background-color:${attrs.background}">${inline}</mark>`;
      if (/^\d+(\.\d+)?$/.test(String(attrs.size || ''))) inline=`<span style="font-size:${Number(attrs.size)}px">${inline}</span>`;
      if (typeof attrs.link === 'string' && /^https?:\/\//.test(attrs.link)) inline = `<a href="${escapeHtml(attrs.link)}">${inline}</a>`;
      line += inline;
      if (i < parts.length - 1) {
        if (attrs.header && Number.isInteger(attrs.header) && attrs.header >= 1 && attrs.header <= 6) output += `<h${attrs.header}>${line}</h${attrs.header}>`;
        else if (attrs.blockquote) output += `<blockquote>${line}</blockquote>`;
        else if (attrs.list === 'ordered') output += `<ol><li>${line}</li></ol>`;
        else if (attrs.list === 'bullet') output += `<ul><li>${line}</li></ul>`;
        else if (attrs.list === 'checked' || attrs.list === 'unchecked') output += `<p><input type="checkbox" disabled${attrs.list === 'checked' ? ' checked' : ''}> ${line}</p>`;
        else output += `<p${['center','right','justify'].includes(attrs.align)?` style="text-align:${attrs.align}"`:''}>${line || '<br>'}</p>`;
        line = '';
      }
    }
  }
  if (line) output += `<p>${line}</p>`;
  return output;
}
function canReadNote(note, uid) {
  return !!note && !note.deletedAt && (note.userId === uid ||
    (Array.isArray(note.liveMemberIds) && note.liveMemberIds.includes(uid)));
}
function personalizeFavorites(notes, uid, ids) {
  const favorites = new Set(ids);
  return notes.map(note => ({...note, isFavorite: note.userId === uid ? !!note.isFavorite : favorites.has(note.noteId)}));
}
function scopedNotes(notes, uid, scope = {kind: 'all'}) {
  const allowed = notes.filter(n => canReadNote(n, uid));
  if (scope.kind === 'notes') {
    if (!Array.isArray(scope.ids) || scope.ids.length > 100 || scope.ids.some(id => typeof id !== 'string')) throw new Error('Invalid note scope');
    const permitted = new Set(allowed.map(n => n.noteId));
    if (scope.ids.some(id => !permitted.has(id))) throw new Error('A selected note is unavailable or not permitted');
    return allowed.filter(n => scope.ids.includes(n.noteId));
  }
  if (scope.kind === 'fav') return allowed.filter(n => n.isFavorite);
  if (scope.kind === 'cat') return allowed.filter(n => n.category === scope.cat);
  if (scope.kind !== 'all') throw new Error('Unknown scope');
  return allowed;
}
function validatedAnswer(answer, permittedIds) {
  if (!answer || !Array.isArray(answer.blocks) || !Array.isArray(answer.sources)) throw new Error('Invalid AI response');
  const set = new Set(permittedIds);
  if (answer.sources.some(id => typeof id !== 'string' || !set.has(id))) throw new Error('Invalid AI source');
  for (const block of answer.blocks) {
    if (['h', 'p', 'quote'].includes(block.t)) {
      if (typeof block.x !== 'string') throw new Error('Invalid text block');
    } else if (['ul', 'ol', 'todo'].includes(block.t)) {
      if (!Array.isArray(block.items) || block.items.some(x => typeof x !== 'string')) throw new Error('Invalid list block');
    } else if (block.t === 'cards') {
      if (!Array.isArray(block.cards) || block.cards.some(c => typeof c.q !== 'string' || typeof c.a !== 'string')) throw new Error('Invalid flashcard block');
    } else throw new Error('Unknown AI block');
  }
  return {blocks: answer.blocks, sources: [...new Set(answer.sources)]};
}
function exportNotes(notes) {
  return notes.map(n => ({id: n.noteId, title: n.title, content: n.content, category: n.category,
    plainText: plainContent(n.content), html: documentHtml(n.content),
    color: n.color || 'blue', favorite: !!n.isFavorite,
    created: n.createdAt?.toDate?.().toISOString() || n.createdAt,
    edited: n.updatedAt?.toDate?.().toISOString() || n.updatedAt,
    createdAt: n.createdAt?.toDate?.().toISOString() || n.createdAt,
    updatedAt: n.updatedAt?.toDate?.().toISOString() || n.updatedAt, attachments: n.attachments || []}));
}
function emailAllowed(settings, kind, now = new Date()) {
  if (settings[kind] === false) return false;
  // Quiet hours follow the user's persisted UTC offset, not the server timezone.
  if (!settings.quietHours) return true;
  const local = new Date(now.getTime() + Number(settings.timezoneOffsetMinutes || 0) * 60000);
  const hour = local.getUTCHours();
  return hour >= 7 && hour < 22;
}
module.exports = {personalizeFavorites, plainContent, documentHtml, canReadNote, scopedNotes, validatedAnswer, exportNotes, emailAllowed};
