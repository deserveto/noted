import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseTestDb} from './pglite_supabase_harness.mjs';
const A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222';
test('account deletion blocks new user and collaborator writes, but permits cleanup and retry',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('n',$1)",[A]));
 await c.asService(t=>t.query("update notes set live_member_ids=array[$1]::uuid[],live_roles=jsonb_build_object($1::text,'edit') where note_id='n'",[B]));
 await c.asService(t=>t.query('select audit_begin_account_deletion($1)',[A]));
 await c.asService(t=>t.query('select audit_begin_account_deletion($1)',[A]));
 await assert.rejects(()=>c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('new',$1)",[A])));
 await assert.rejects(()=>c.asUser(B,t=>t.query("select commit_note_revision('n',0,'x','edit','Personal','blue',false,'[]')")));
 await assert.rejects(()=>c.asUser(A,t=>t.query("insert into storage.objects(bucket_id,name,owner) values('avatars',$1,$2)",[ `users/${A}/a.png`, A])));
 await c.asService(t=>t.query("delete from notes where note_id='n'"));
 } finally {await c.db.close()}
});
test('deleting accounts cannot grant, receive sharing, or upload through another owner',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asService(t=>t.query("insert into connection_requests(connection_id,from_user_id,to_user_id,status) values('c',$1,$2,'accepted')",[A,B]));
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('n',$1)",[A]));
 await c.asService(t=>t.query("select audit_set_live_role('n',$1,$2,'edit')",[A,B]));
 await c.asService(t=>t.query('select audit_begin_account_deletion($1)',[A]));
 await assert.rejects(()=>c.asUser(B,t=>t.query("insert into storage.objects(bucket_id,name,owner) values('note-media',$1,$2)",[ `users/${B}/notes/n/a.png`,B])));
 await assert.rejects(()=>c.asService(t=>t.query("select audit_set_live_role('n',$1,$2,'view')",[A,B])));
 await assert.rejects(()=>c.asService(t=>t.query("select audit_queue_note_copy('n',$1,$2)",[A,B])));
 await c.asService(t=>t.query("delete from connection_requests where connection_id='c'"));
 } finally {await c.db.close()}
});
test('account deletion reports pending copy before media cleanup and prevents new reservations',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("select audit_reserve_copy_cleanup('copy',$1)",[A]));
 const r=await c.asService(t=>t.query('select audit_begin_account_deletion($1) as r',[A])); assert.equal(r.rows[0].r.pendingCopies,1);
 await assert.rejects(()=>c.asService(t=>t.query("select audit_reserve_copy_cleanup('another',$1)",[A])));
 await c.asService(t=>t.query("select audit_claim_copy_cleanup('copy',now())"));
 await c.asService(t=>t.query("select audit_finish_copy_cleanup('copy')"));
 assert.equal((await c.asService(t=>t.query('select audit_begin_account_deletion($1) as r',[A]))).rows[0].r.pendingCopies,0);
 } finally {await c.db.close()}
});
