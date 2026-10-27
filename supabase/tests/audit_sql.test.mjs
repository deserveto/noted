import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupabaseTestDb } from './pglite_supabase_harness.mjs';
const A='11111111-1111-4111-8111-111111111111', B='22222222-2222-4222-8222-222222222222';
test('audit: untrusted signup metadata cannot claim a legacy identity', async () => {
 const c=await createSupabaseTestDb(); try { await c.createAuthUser({id:A,email:'a@example.com',name:'A',legacyFirebaseUid:'claimed'}); const r=await c.asUser(A,t=>t.query('select legacy_firebase_uid from profiles')); assert.equal(r.rows[0].legacy_firebase_uid,null); } finally {await c.db.close()}
});
test('audit: rejected peers cannot view profile; malformed settings cannot be stored', async () => {
 const c=await createSupabaseTestDb(); try { await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'}); await c.asService(t=>t.query("insert into connection_requests (connection_id,from_user_id,to_user_id,status) values ('r',$1,$2,'rejected')",[A,B])); const r=await c.asUser(A,t=>t.query('select public.can_view_peer_profile($1) as allowed',[B])); assert.equal(r.rows[0].allowed,false); await assert.rejects(()=>c.asUser(A,t=>t.query(`select public.merge_user_settings('{"nLive":"bad"}'::jsonb, null)`))); } finally {await c.db.close()}
});
test('audit: bounded activity and favorite survive a concurrent content save', async () => {
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'.repeat(120)}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values ('n',$1,$2)",[A,'T'.repeat(1000)]));
 await c.asService(t=>t.query("update notes set live_member_ids=array[$1]::uuid[],live_roles=jsonb_build_object($1::text,'view') where note_id='n'",[B]));
 await c.asUser(A,t=>t.query("update notes set is_favorite=true where note_id='n'"));
 const r=await c.asUser(A,t=>t.query("select commit_note_revision('n',0,$1,'body','Personal','blue',false,'[]') as result",['T'.repeat(1000)]));
 assert.equal(r.rows[0].result.note.is_favorite,true);
 const notifications=await c.asService(t=>t.query("select title from notifications where user_id=$1",[B])); assert.equal(notifications.rows.length,1); assert.equal(notifications.rows[0].title.length,300);
 await c.asUser(A,t=>t.query("update notes set content='direct' where note_id='n'"));
 const stale=await c.asUser(A,t=>t.query("select commit_note_revision('n',1,'x','stale','Personal','blue',false,'[]') as result")); assert.equal(stale.rows[0].result.committed,false);
 } finally {await c.db.close()}
});
test('audit: atomic sharing RPCs enforce changes, claim once and limit requests', async () => {
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asService(t=>t.query("insert into connection_requests(connection_id,from_user_id,to_user_id,status) values('c',$1,$2,'accepted')",[A,B]));
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('n',$1,'Title')",[A]));
 await assert.rejects(()=>c.asUser(A,t=>t.query("select audit_set_live_role('n',$1,$2,'edit')",[A,B])));
 const role=()=>c.asService(t=>t.query("select audit_set_live_role('n',$1,$2,'edit') as r",[A,B])); assert.equal((await role()).rows[0].r.changed,true); assert.equal((await role()).rows[0].r.changed,false);
 const queue=()=>c.asService(t=>t.query("select audit_queue_note_copy('n',$1,$2) as r",[A,B])); assert.equal((await queue()).rows[0].r.changed,true); assert.equal((await queue()).rows[0].r.changed,false);
 const copy=JSON.stringify({note_id:'copy',content:'copied',attachments:[]});
 await c.asService(t=>t.query("select audit_accept_note_copy('n',$1,0,$2::jsonb)",[B,copy]));
 await assert.rejects(()=>c.asService(t=>t.query("select audit_accept_note_copy('n',$1,0,$2::jsonb)",[B,copy])));
 await c.asService(t=>t.query('select audit_remove_user_memberships($1)',[B]));
 const n=await c.asService(t=>t.query("select live_member_ids,shared_with_user_ids from notes where note_id='n'")); assert.deepEqual(n.rows[0].live_member_ids,[]); assert.deepEqual(n.rows[0].shared_with_user_ids,[]);
 const limit=()=>c.asService(t=>t.query("select check_rate_limit($1,'test',2,60) as ok",[A])); assert.equal((await limit()).rows[0].ok,true); assert.equal((await limit()).rows[0].ok,true); assert.equal((await limit()).rows[0].ok,false);
 } finally {await c.db.close()}
});
test('audit: pending peer remains visible and existing malformed preferences cannot abort triggers', async () => {
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asService(t=>t.query("insert into connection_requests(connection_id,from_user_id,to_user_id,status) values('c',$1,$2,'pending')",[A,B]));
 assert.equal((await c.asUser(A,t=>t.query('select can_view_peer_profile($1) as v',[B]))).rows[0].v,true);
 await c.db.exec('alter table user_settings disable trigger audit_validate_preferences');
 await c.asService(t=>t.query(`update user_settings set preferences='{"nLive":"bad","nRequests":"bad"}' where user_id=$1`,[A]));
 await c.db.exec('alter table user_settings enable trigger audit_validate_preferences');
 await c.asService(t=>t.query("update connection_requests set status='accepted' where connection_id='c'"));
 await c.asUser(B,t=>t.query("insert into notes(note_id,user_id,title) values('n',$1,'n')",[B]));
 await c.asService(t=>t.query("update notes set live_member_ids=array[$1]::uuid[],live_roles=jsonb_build_object($1::text,'view') where note_id='n'",[A]));
 const committed=await c.asUser(B,t=>t.query("select commit_note_revision('n',0,'n','new','Personal','blue',false,'[]') as r")); assert.equal(committed.rows[0].r.committed,true);
 const notices=await c.asService(t=>t.query('select type from notifications where user_id=$1 order by type',[A])); assert.deepEqual(notices.rows.map(x=>x.type),['live','request']);
 await c.asUser(A,t=>t.query(`select merge_user_settings('{"textSize":16,"theme":"dark"}'::jsonb,null)`));
 } finally {await c.db.close()}
});
test('audit: expired limit resets; stale copy claim leaves pending intact', async () => {
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asService(t=>t.query("insert into rate_limits(user_id,operation,count,reset_at) values($1,'expired',9,now()-interval '1 second')",[A]));
 assert.equal((await c.asService(t=>t.query("select check_rate_limit($1,'expired',1,60) as r",[A]))).rows[0].r,true);
 assert.equal((await c.asService(t=>t.query("select check_rate_limit($1,'expired',1,60) as r",[A]))).rows[0].r,false);
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('n',$1)",[A]));
 await c.asService(t=>t.query("update notes set pending_shared_with_user_ids=array[$1]::uuid[], revision=1 where note_id='n'",[B]));
 await assert.rejects(()=>c.asService(t=>t.query("select audit_accept_note_copy('n',$1,0,'{\"note_id\":\"copy\"}'::jsonb)",[B])));
 const r=await c.asService(t=>t.query("select pending_shared_with_user_ids from notes where note_id='n'")); assert.deepEqual(r.rows[0].pending_shared_with_user_ids,[B]);
 } finally {await c.db.close()}
});
test('audit: long fallback actor email is bounded for activity notifications', async () => {
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:`${'a'.repeat(220)}@example.com`,name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asService(t=>t.query("update profiles set name='' where id=$1",[A]));
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('n',$1,'Title')",[A]));
 await c.asService(t=>t.query("update notes set live_member_ids=array[$1]::uuid[],live_roles=jsonb_build_object($1::text,'view') where note_id='n'",[B]));
 await c.asUser(A,t=>t.query("select commit_note_revision('n',0,'Title','body','Personal','blue',false,'[]')"));
 const r=await c.asService(t=>t.query('select actor_name from notifications where user_id=$1',[B])); assert.equal(r.rows[0].actor_name.length,200);
 } finally {await c.db.close()}
});
