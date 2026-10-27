import test from 'node:test';
import assert from 'node:assert/strict';
import { deleteNoteMediaObjects, deleteStoragePrefixRecursively } from '../functions/_shared/media.ts';

test('storage deletion rejects returned and thrown failures', async () => {
  for (const remove of [async () => ({error:{message:'failed'}}), async () => { throw Error('failed'); }]) {
    const storage = {from: () => ({remove, list: async () => ({data: [], error: null})})};
    await assert.rejects(deleteNoteMediaObjects({storage, noteId:'n', attachments:[{path:'users/u/notes/n/f'}]}));
  }
});

test('recursive deletion fails closed on list errors', async () => {
  const storage = {from: () => ({list: async () => ({data:null,error:{message:'failed'}}),remove:async()=>({error:null})})};
  await assert.rejects(deleteStoragePrefixRecursively(storage,'note-media','users/u'));
});
import { handleNotedAiRequest } from '../functions/noted-ai/handler.ts';
import { handleScheduledMaintenanceRequest } from '../functions/scheduled-maintenance/handler.ts';
import { fetchAllPages } from '../functions/_shared/pagination.ts';

test('AI refuses output if an uncited supplied note is revoked during generation', async () => {
  let reads = 0, saves = 0;
  const notes = [{id:'a',title:'A',content:'public',category:'Personal'}, {id:'b',title:'B',content:'secret',category:'Personal'}];
  const store = {checkRateLimit:async()=>true,getSettings:async()=>({}),getAiRequest:async()=>null,upsertAiRequest:async()=>{},listAccessibleNotes:async()=>++reads === 1 ? notes : [notes[0]],commitAiExchange:async()=>{saves++;}};
  const req = new Request('https://local', {method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({prompt:'summarize'})});
  const response = await handleNotedAiRequest(req,{verifyToken:async()=>({uid:'u',email:'u@example.com'}),store,env:{aiApiKey:'test'},fetchImpl:async()=>new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({intent:'answer',blocks:[{t:'p',x:'secret'}],sources:['a']})}}]}))});
  assert.equal(response.status,403); assert.equal(saves,0); assert.ok(!(await response.text()).includes('secret'));
});

test('pagination fetches every row beyond API cap', async () => {
  const rows = Array.from({length:1201},(_,i)=>({id:i}));
  const result = await fetchAllPages(()=>({order(){return this},async range(a,b){return {data:rows.slice(a,b+1),error:null}}}),'id');
  assert.equal(result.length,1201);
});

test('quiet hours defer queued emails for later', async () => {
  const marked=[];
  const store={listCopyCleanup:async()=>[],listCopySweeps:async()=>[],listPendingEmailNotifications:async()=>[{id:'n',user_id:'u',type:'live',title:'title',body:'body'}],getRecipientContext:async()=>({email:'u@example.com',preferences:{},timezoneOffsetMinutes:0}),markNotificationEmailDispatched:async id=>marked.push(id),listRecapCandidates:async()=>[],cleanupEphemeralRows:async()=>{}};
  const req=new Request('https://local',{method:'POST',headers:{'x-cron-secret':'secret','Content-Type':'application/json'},body:JSON.stringify({job:'hourly'})});
  const response=await handleScheduledMaintenanceRequest(req,{cronSecret:'secret',store,storage:{},env:{},now:()=>new Date('2026-10-26T23:00:00Z')});
  assert.equal(response.status,200); assert.deepEqual(marked,[]);
});
import { handleConnectionsRequest } from '../functions/connections/handler.ts';
import { handleNoteSharingRequest } from '../functions/note-sharing/handler.ts';
const user = '11111111-1111-4111-8111-111111111111', target = '22222222-2222-4222-8222-222222222222';
const request = payload => new Request('https://local',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify(payload)});
const verify = async()=>({uid:user,email:'me@example.com'});

test('direct invitations do not email existing accounts', async()=>{
 let sent=0;
 const response=await handleConnectionsRequest(request({action:'inviteByEmail',email:'other@example.com'}),{verifyToken:verify,store:{checkRateLimit:async()=>true,findProfileByEmail:async()=>({id:target})},env:{appUrl:'https://noted.example'},fetchImpl:async()=>{sent++;return new Response('{}')}});
 assert.equal(response.status,200);assert.equal(sent,0);
});

test('unchanged sharing requests do not notify',async()=>{
 let calls=0,notifications=0;
 const note={note_id:'n',user_id:user,deleted_at:null,title:'title',source_owner_id:null};
 const store={checkRateLimit:async()=>{calls++;return true},getNote:async()=>note,hasAcceptedConnection:async()=>true,getUserSettings:async()=>({preferences:{},timezoneOffsetMinutes:0}),setLiveRole:async()=>({changed:false,note}),queueNoteCopy:async()=>({changed:false,note}),insertNotification:async()=>{notifications++;return 'n'}};
 for (const action of ['setLiveRole','queueNoteCopy']) {
   const response=await handleNoteSharingRequest(request({action,noteId:'n',targetUserId:target,role:'edit'}),{verifyToken:verify,store,storage:{},env:{}});
   assert.equal(response.status,200);
 }
 assert.equal(calls,2);assert.equal(notifications,0);
});
import { handleAccountRequest } from '../functions/account/handler.ts';
test('account retains database and auth when storage cleanup fails',async()=>{
 let deleted=0;
 const store={beginAccountDeletion:async()=>0,listOwnedNotesForDeletion:async()=>[{note_id:'n',attachments:[]}],removeUserFromCollaborations:async()=>deleted++,deleteAllUserData:async()=>deleted++,deleteAuthUser:async()=>deleted++};
 const storage={from:()=>({list:async()=>({data:null,error:{message:'offline'}})})};
 const response=await handleAccountRequest(request({action:'deleteAccount',currentPassword:'password'}),{verifyToken:verify,verifyPassword:async()=>true,store,storage});
 assert.equal(response.status,500);assert.equal(deleted,0);
});

test('recursive storage cleanup visits nested paths and shifted pages',async()=>{
 const files=new Set(Array.from({length:505},(_,i)=>`users/u/notes/n/f${String(i).padStart(3,'0')}`));files.add('users/u/notes/n/nested/file');
 const storage={from:()=>({list:async(prefix,{limit,offset})=>{const values=new Map();for(const file of files){if(!file.startsWith(prefix+'/'))continue;const rest=file.slice(prefix.length+1), slash=rest.indexOf('/');const name=slash<0?rest:rest.slice(0,slash);values.set(name,slash<0?{name,id:'id'}:{name,id:null,metadata:null});}return {data:[...values.values()].sort((a,b)=>a.name.localeCompare(b.name)).slice(offset,offset+limit),error:null}},remove:async paths=>{for(const p of paths)files.delete(p);return {error:null}}})};
 const count=await deleteStoragePrefixRecursively(storage,'note-media','users/u/notes/n');
 assert.equal(count,506);assert.equal(files.size,0);
});
test('AI rejects unattributed or invented selected text before provider', async()=>{
 let calls=0;
 const store={checkRateLimit:async()=>true,getSettings:async()=>({}),getAiRequest:async()=>null,upsertAiRequest:async()=>{},listAccessibleNotes:async()=>[{id:'a',title:'A',content:'actual text',category:'Personal'}]};
 for (const payload of [{selection:'secret'}, {selection:'invented',selectionNoteId:'a'}, {selection:'actual',selectionNoteId:'revoked'}]) {
   const response=await handleNotedAiRequest(request({prompt:'summarize',...payload}),{verifyToken:verify,store,env:{aiApiKey:'test'},fetchImpl:async()=>{calls++;return new Response('{}')}});
   assert.ok(response.status>=400);
 }
 assert.equal(calls,0);
});

test('AI does not send unmarked legacy assistant history to provider',async()=>{
 let messages;
 const store={checkRateLimit:async()=>true,getSettings:async()=>({}),getAiRequest:async()=>null,upsertAiRequest:async()=>{},listAccessibleNotes:async()=>[{id:'a',title:'A',content:'public',category:'Personal'}],listRecentChatMessages:async()=>[{role:'ai',blocks:[{t:'p',x:'legacy secret'}],sources:['a']}],commitAiExchange:async()=>null};
 const response=await handleNotedAiRequest(request({prompt:'summarize',chatId:'chat'}),{verifyToken:verify,store,env:{aiApiKey:'test'},fetchImpl:async(_url,opts)=>{messages=JSON.parse(opts.body).messages;return new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({intent:'answer',blocks:[{t:'p',x:'ok'}],sources:['a']})}}]}))}});
 assert.equal(response.status,200);assert.ok(!JSON.stringify(messages).includes('legacy secret'));
});

test('copy acceptance succeeds even if ancillary notification fails',async()=>{
 const note={note_id:'n',user_id:target,deleted_at:null,title:'x'.repeat(1000),content:'body',attachments:[],revision:0,pending_shared_with_user_ids:[user]};let accepted=0;
 const store={reserveCopyCleanup:async()=>{},completeCopyCleanup:async()=>{},checkRateLimit:async()=>true,getNote:async()=>note,getProfile:async()=>({name:'a',email:'a@example.com'}),getUserSettings:async()=>({preferences:{},timezoneOffsetMinutes:0}),acceptNoteCopy:async()=>accepted++,insertNotification:async()=>{throw Error('unavailable')}};
 const response=await handleNoteSharingRequest(request({action:'acceptNoteCopy',noteId:'n'}),{verifyToken:verify,store,storage:{from:()=>({remove:async()=>({error:null})})},env:{}});
 assert.equal(response.status,200);assert.equal(accepted,1);
});
test('scheduler scans past quiet-hour rows while bounding email attempts',async()=>{
 const quiet=Array.from({length:200},(_,i)=>({id:`q${i}`,user_id:'quiet',type:'live',title:'t',body:'b'})); const eligible={id:'later',user_id:'awake',type:'live',title:'t',body:'b'};const rows=[...quiet,eligible],marked=[],pages=[];
 const store={listCopyCleanup:async()=>[],listCopySweeps:async()=>[],listPendingEmailNotifications:async(limit,offset)=>{pages.push([limit,offset]);return rows.slice(offset,offset+limit)},getRecipientContext:async uid=>({email:'u@example.com',preferences:{},timezoneOffsetMinutes:uid==='quiet'?0:-600}),markNotificationEmailDispatched:async id=>marked.push(id),listRecapCandidates:async()=>[],cleanupEphemeralRows:async()=>{}};
 const response=await handleScheduledMaintenanceRequest(new Request('https://local',{method:'POST',headers:{'x-cron-secret':'secret','Content-Type':'application/json'},body:JSON.stringify({job:'hourly'})}),{cronSecret:'secret',store,storage:{},env:{resendApiKey:'x',emailFrom:'x'},fetchImpl:async()=>new Response('{}'),now:()=>new Date('2026-10-26T23:00:00Z')});
 assert.equal(response.status,200);assert.deepEqual(marked,['later']);assert.deepEqual(pages,[[200,0],[200,200]]);
});
test('permanent deletion does not clean media for a note restored before claim',async()=>{
 let removed=0,finalized=0;
 const store={getNote:async()=>({note_id:'n',user_id:user,deleted_at:'2026-01-01',attachments:[]}),claimNoteDeletion:async()=>({claimed:false,note:null}),finalizeNoteDeletion:async()=>{finalized++;return true}};
 const response=await handleNoteSharingRequest(request({action:'deleteNote',noteId:'n'}),{verifyToken:verify,store,storage:{from:()=>({list:async()=>{removed++;return {data:[],error:null}}})},env:{}});
 assert.equal(response.status,409);assert.equal(removed,0);assert.equal(finalized,0);
});
test('account deletion establishes barrier before enumerating or cleaning',async()=>{
 const actions=[];
 const store={beginAccountDeletion:async()=>{actions.push('begin');return 0},listOwnedNotesForDeletion:async()=>{actions.push('list');return []},removeUserFromCollaborations:async()=>{},deleteAllUserData:async()=>{},deleteAuthUser:async()=>{}};
 const storage={from:()=>({list:async()=>({data:[],error:null})})};
 const response=await handleAccountRequest(request({action:'deleteAccount',currentPassword:'password'}),{verifyToken:verify,verifyPassword:async()=>true,store,storage});
 assert.equal(response.status,200);assert.deepEqual(actions,['begin','list']);
});
test('selected note outside ranked context is reauthorized after provider',async()=>{
 const notes=Array.from({length:9},(_,i)=>({id:`n${i}`,title:`note ${i}`,content:`content ${i}`,category:'Personal'})); let reads=0,saved=0,called=0;
 const store={checkRateLimit:async()=>true,getSettings:async()=>({}),getAiRequest:async()=>null,upsertAiRequest:async()=>{},listAccessibleNotes:async()=>++reads===1?notes:notes.filter(n=>n.id!=='n8'),commitAiExchange:async()=>saved++};
 const response=await handleNotedAiRequest(request({prompt:'content',selection:'content 8',selectionNoteId:'n8'}),{verifyToken:verify,store,env:{aiApiKey:'test'},fetchImpl:async()=>{called++;return new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({intent:'answer',blocks:[{t:'p',x:'answer'}],sources:[]})}}]}))}});
 assert.equal(called,1);assert.equal(response.status,403);assert.equal(saved,0);
});

test('claimed deletion remains retryable when storage fails',async()=>{
 let finalized=0;
 const note={note_id:'n',user_id:user,deleted_at:'2026-01-01',attachments:[]};
 const store={getNote:async()=>note,claimNoteDeletion:async()=>({claimed:true,note}),finalizeNoteDeletion:async()=>{finalized++;return true}};
 const response=await handleNoteSharingRequest(request({action:'deleteNote',noteId:'n'}),{verifyToken:verify,store,storage:{from:()=>({list:async()=>({data:null,error:{message:'unavailable'}})})},env:{}});
 assert.equal(response.status,500);assert.equal(finalized,0);
});
test('copy reserves cleanup before writing blobs and retains reservation on failure',async()=>{
 const events=[];
 const note={note_id:'n',user_id:user,deleted_at:null,title:'N',content:'',attachments:[{name:'f',path:`users/${user}/notes/n/f`}],revision:0,live_member_ids:[],color:'blue'};
 const store={checkRateLimit:async()=>true,getNote:async()=>note,reserveCopyCleanup:async()=>events.push('reserve'),completeCopyCleanup:async()=>events.push('complete')};
 const storage={from:()=>({copy:async()=>{events.push('copy');return {error:{message:'unavailable'}}},remove:async()=>({error:null})})};
 const response=await handleNoteSharingRequest(request({action:'duplicateNote',noteId:'n'}),{verifyToken:verify,store,storage,env:{}});
 assert.equal(response.status,412);assert.deepEqual(events,['reserve','copy']);
});
test('scheduler retries failed reserved copy cleanup without touching committed copies',async()=>{
 let fail=true;const finished=[],claims=[];
 const store={listCopySweeps:async()=>[],listCopyCleanup:async()=>[{note_id:'orphan',user_id:user},{note_id:'committed',user_id:user}],claimCopyCleanup:async(id)=>{claims.push(id);return id==='committed'?{claimed:false,userId:null}:{claimed:true,userId:user}},finishCopyCleanup:async id=>finished.push(id),listPendingEmailNotifications:async()=>[],listRecapCandidates:async()=>[],cleanupEphemeralRows:async()=>{}};
 const storage={from:()=>({list:async()=>fail?{data:null,error:{message:'offline'}}:{data:[{name:'f',id:'file'}],error:null},remove:async()=>({error:null})})};
 const run=()=>handleScheduledMaintenanceRequest(new Request('https://local',{method:'POST',headers:{'x-cron-secret':'secret','Content-Type':'application/json'},body:JSON.stringify({job:'hourly'})}),{cronSecret:'secret',store,storage,env:{},now:()=>new Date('2026-10-26T12:00:00Z')});
 assert.equal((await run()).status,200);assert.deepEqual(finished,[]);fail=false;
 assert.equal((await run()).status,200);assert.deepEqual(finished,['orphan']);assert.deepEqual(claims,['orphan','committed','orphan','committed']);
});
test('account deletion waits for in-flight copy reservations before cleanup',async()=>{
 let listed=0;
 const store={beginAccountDeletion:async()=>2,listOwnedNotesForDeletion:async()=>{listed++;return []}};
 const response=await handleAccountRequest(request({action:'deleteAccount',currentPassword:'password'}),{verifyToken:verify,verifyPassword:async()=>true,store,storage:{}});
 assert.equal(response.status,503);assert.equal(listed,0);
});
test('account cleanup sweeps entire user media prefix including orphan and collaborator uploads',async()=>{
 const paths=new Set([`users/${user}/notes/other/attached`,`users/${user}/notes/orphan/file`]);let authDeleted=0;
 const store={beginAccountDeletion:async()=>0,listOwnedNotesForDeletion:async()=>[],removeUserFromCollaborations:async()=>{},deleteAllUserData:async()=>{},deleteAuthUser:async()=>authDeleted++};
 const storage={from:bucket=>({list:async(prefix,{limit,offset})=>{if(bucket==='avatars')return {data:[],error:null};const values=new Map();for(const path of paths){if(!path.startsWith(prefix+'/'))continue;const rest=path.slice(prefix.length+1), slash=rest.indexOf('/');const name=slash<0?rest:rest.slice(0,slash);values.set(name,slash<0?{name,id:'id'}:{name,id:null,metadata:null});}return {data:[...values.values()].slice(offset,offset+limit),error:null}},remove:async items=>{for(const item of items)paths.delete(item);return {error:null}}})};
 const response=await handleAccountRequest(request({action:'deleteAccount',currentPassword:'password'}),{verifyToken:verify,verifyPassword:async()=>true,store,storage});
 assert.equal(response.status,200);assert.equal(paths.size,0);assert.equal(authDeleted,1);
});

test('account prefix failure retains auth and can be retried',async()=>{
 let fail=true,deleted=0;
 const store={beginAccountDeletion:async()=>0,listOwnedNotesForDeletion:async()=>[],removeUserFromCollaborations:async()=>{},deleteAllUserData:async()=>{},deleteAuthUser:async()=>deleted++};
 const storage={from:bucket=>({list:async()=>bucket==='note-media'&&fail?{data:null,error:{message:'offline'}}:{data:[],error:null}})};
 const run=()=>handleAccountRequest(request({action:'deleteAccount',currentPassword:'password'}),{verifyToken:verify,verifyPassword:async()=>true,store,storage});
 assert.equal((await run()).status,500);assert.equal(deleted,0);fail=false;assert.equal((await run()).status,200);assert.equal(deleted,1);
});
test('scheduler revisits tombstoned copy prefix and removes later-arriving media',async()=>{
 let runs=0; const files=new Set(); const swept=[];
 const store={listCopyCleanup:async()=>[],listCopySweeps:async()=>[{note_id:'lost',user_id:user}],recordCopySweep:async id=>swept.push(id),listPendingEmailNotifications:async()=>[],listRecapCandidates:async()=>[],cleanupEphemeralRows:async()=>{}};
 const storage={from:()=>({list:async(prefix)=>({data:[...files].filter(f=>f.startsWith(prefix+'/')).map(f=>({name:f.slice(prefix.length+1),id:'id'})),error:null}),remove:async paths=>{for(const p of paths)files.delete(p);return {error:null}}})};
 const run=()=>handleScheduledMaintenanceRequest(new Request('https://local',{method:'POST',headers:{'x-cron-secret':'secret','Content-Type':'application/json'},body:JSON.stringify({job:'hourly'})}),{cronSecret:'secret',store,storage,env:{},now:()=>new Date('2026-10-26T12:00:00Z')});
 assert.equal((await run()).status,200);files.add(`users/${user}/notes/lost/late`);assert.equal((await run()).status,200);assert.equal(files.size,0);assert.deepEqual(swept,['lost','lost']);
});
test('claimed note cleanup removes unreferenced collaborator uploads under their prefix',async()=>{
 const files=new Set([`users/${user}/notes/n/owner`, `users/${target}/notes/n/orphan`]);let finalized=0;
 const note={note_id:'n',user_id:user,deleted_at:'2026-01-01',attachments:[]};const store={getNote:async()=>note,claimNoteDeletion:async()=>({claimed:true,note}),finalizeNoteDeletion:async()=>{finalized++;return true}};
 const storage={from:()=>({list:async(prefix,{limit,offset})=>{const entries=new Map();for(const f of files){if(!f.startsWith(prefix+'/'))continue;const rest=f.slice(prefix.length+1),j=rest.indexOf('/'),name=j<0?rest:rest.slice(0,j);entries.set(name,j<0?{name,id:'id'}:{name,id:null,metadata:null})}return {data:[...entries.values()].slice(offset,offset+limit),error:null}},remove:async paths=>{for(const p of paths)files.delete(p);return {error:null}}})};
 const response=await handleNoteSharingRequest(request({action:'deleteNote',noteId:'n'}),{verifyToken:verify,store,storage,env:{}});
 assert.equal(response.status,200);assert.equal(finalized,1);assert.equal(files.size,0);
});
test('AI fails closed when dependency authorization changes at atomic commit',async()=>{
 let committed=0;
 const store={checkRateLimit:async()=>true,getSettings:async()=>({aiHistory:false}),getAiRequest:async()=>null,upsertAiRequest:async()=>{},listAccessibleNotes:async()=>[{id:'a',title:'A',content:'secret',category:'Personal'}],commitAiExchange:async()=>{committed++;throw Error('permission changed')}};
 const response=await handleNotedAiRequest(request({prompt:'summary'}),{verifyToken:verify,store,env:{aiApiKey:'test'},fetchImpl:async()=>new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({intent:'answer',blocks:[{t:'p',x:'secret'}],sources:['a']})}}]}))});
 assert.ok(response.status>=400);assert.equal(committed,1);assert.ok(!(await response.text()).includes('secret'));
});
test('scheduler examines at most 1000 quiet-hour candidates per run',async()=>{
 const pages=[],rows=Array.from({length:1200},(_,i)=>({id:String(i),user_id:'quiet',type:'live',title:'t',body:'b'}));let examined=0;
 const store={listCopyCleanup:async()=>[],listCopySweeps:async()=>[],listPendingEmailNotifications:async(limit,offset)=>{pages.push([limit,offset]);return rows.slice(offset,offset+limit)},getRecipientContext:async()=>{examined++;return {email:'u@example.com',preferences:{},timezoneOffsetMinutes:0}},listRecapCandidates:async()=>[],cleanupEphemeralRows:async()=>{}};
 const response=await handleScheduledMaintenanceRequest(new Request('https://local',{method:'POST',headers:{'x-cron-secret':'secret','Content-Type':'application/json'},body:JSON.stringify({job:'hourly'})}),{cronSecret:'secret',store,storage:{},env:{},now:()=>new Date('2026-10-26T23:00:00Z')});
 assert.equal(response.status,200);assert.equal(examined,1000);assert.equal(pages.length,5);
});
import { createSupabaseScheduledMaintenanceStore } from '../functions/scheduled-maintenance/handler.ts';
test('scheduler fetches notifications through durable rotation cursor',async()=>{
 const calls=[];const store=createSupabaseScheduledMaintenanceStore({rpc:async(name,args)=>{calls.push([name,args]);return {data:[],error:null}}});
 assert.deepEqual(await store.listPendingEmailNotifications(200,400),[]);assert.deepEqual(calls,[['audit_take_email_batch',{p_limit:200}]]);
});
test('scheduler does not retry the same wrapped email twice per run',async()=>{
 const batch=Array.from({length:200},(_,i)=>({id:String(i),user_id:'u',type:'live',title:'t',body:'b'}));let sent=0, examined=0;
 const store={listCopyCleanup:async()=>[],listCopySweeps:async()=>[],listPendingEmailNotifications:async()=>batch,getRecipientContext:async()=>{examined++;return {email:'u@example.com',preferences:{},timezoneOffsetMinutes:0}},listRecapCandidates:async()=>[],cleanupEphemeralRows:async()=>{}};
 const response=await handleScheduledMaintenanceRequest(new Request('https://local',{method:'POST',headers:{'x-cron-secret':'secret','Content-Type':'application/json'},body:JSON.stringify({job:'hourly'})}),{cronSecret:'secret',store,storage:{},env:{resendApiKey:'x',emailFrom:'x'},fetchImpl:async()=>{sent++;return new Response('',{status:503})},now:()=>new Date('2026-10-26T23:00:00Z')});
 assert.equal(response.status,200);assert.equal(sent,0);assert.equal(examined,200);
});
