import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseTestDb} from './pglite_supabase_harness.mjs';
const A='11111111-1111-4111-8111-111111111111';
test('claimed trashed notes cannot be restored, edited or reused and claims retry',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('n',$1)",[A]));
 await c.asUser(A,t=>t.query("update notes set deleted_at=now() where note_id='n'"));
 const claim=()=>c.asService(t=>t.query("select audit_claim_note_deletion('n',$1,null) as r",[A]));
 assert.equal((await claim()).rows[0].r.claimed,true); assert.equal((await claim()).rows[0].r.claimed,true);
 await assert.rejects(()=>c.asUser(A,t=>t.query("update notes set deleted_at=null where note_id='n'")));
 await assert.rejects(()=>c.asUser(A,t=>t.query("update notes set content='new' where note_id='n'")));
 assert.equal((await c.asService(t=>t.query("select audit_finalize_note_deletion('n',$1) as r",[A]))).rows[0].r,true);
 await assert.rejects(()=>c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('n',$1)",[A])));
 } finally {await c.db.close()}
});
test('claim checks owner and cutoff against locked row and blocks media writes',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id) values('n',$1)",[A]));
 assert.equal((await c.asService(t=>t.query("select audit_claim_note_deletion('n',$1,null) as r",[A]))).rows[0].r.claimed,false);
 await c.asUser(A,t=>t.query("update notes set deleted_at=now() where note_id='n'"));
 assert.equal((await c.asService(t=>t.query("select audit_claim_note_deletion('n',$1,now()-interval '1 day') as r",[A]))).rows[0].r.claimed,false);
 await assert.rejects(()=>c.asUser(A,t=>t.query("insert into storage.objects(bucket_id,name,owner) values('note-media',$1,$2)",[ `users/${A}/notes/n/a.png`, A])));
 assert.equal((await c.asService(t=>t.query("select audit_claim_note_deletion('n',$1,null) as r",[A]))).rows[0].r.claimed,true);
 await assert.rejects(()=>c.asUser(A,t=>t.query("update notes set deletion_started_at=null where note_id='n'")));
 } finally {await c.db.close()}
});
test('AI dependency provenance is protected from client updates',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("insert into ai_chats(user_id,chat_id) values($1,'c')",[A]));
 await c.asService(t=>t.query("insert into ai_messages(id,user_id,chat_id,role,context_dependencies) values('m',$1,'c','ai','[\"note\"]')",[A]));
 await assert.rejects(()=>c.asUser(A,t=>t.query("update ai_messages set context_dependencies='[]' where id='m'")));
 await c.asUser(A,t=>t.query("update ai_messages set fb='up' where id='m'"));
 } finally {await c.db.close()}
});
test('copy cleanup claims exclude note insertion and retain reservation on failure',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("select audit_reserve_copy_cleanup('copy',$1)",[A]));
 let r=await c.asService(t=>t.query("select audit_claim_copy_cleanup('copy',now()) as r")); assert.equal(r.rows[0].r.claimed,true);
 r=await c.asService(t=>t.query("select audit_claim_copy_cleanup('copy',now()) as r")); assert.equal(r.rows[0].r.claimed,true);
 await assert.rejects(()=>c.asService(t=>t.query("insert into notes(note_id,user_id) values('copy',$1)",[A])));
 await c.asService(t=>t.query("select audit_finish_copy_cleanup('copy')"));
 await assert.rejects(()=>c.asService(t=>t.query("insert into notes(note_id,user_id) values('copy',$1)",[A])));
 } finally {await c.db.close()}
});
test('completed copy is retained when stale cleanup races',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("select audit_reserve_copy_cleanup('copy',$1)",[A]));
 await c.asService(t=>t.query("insert into notes(note_id,user_id) values('copy',$1)",[A]));
 const r=await c.asService(t=>t.query("select audit_claim_copy_cleanup('copy',now()) as r")); assert.equal(r.rows[0].r.claimed,false);
 assert.equal((await c.asService(t=>t.query("select count(*)::int as n from notes where note_id='copy'"))).rows[0].n,1);
 } finally {await c.db.close()}
});
test('abandoned copy sweeps persist and rotate after attempts',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("select audit_reserve_copy_cleanup('a',$1)",[A]));
 await c.asService(t=>t.query("select audit_reserve_copy_cleanup('b',$1)",[A]));
 await c.asService(t=>t.query("select audit_claim_copy_cleanup('a',now())"));
 await c.asService(t=>t.query("select audit_claim_copy_cleanup('b',now())"));
 await c.asService(t=>t.query("select audit_finish_copy_cleanup('a')"));
 let r=await c.asService(t=>t.query('select * from audit_list_copy_sweeps(1)')); assert.equal(r.rows[0].note_id,'a');
 await c.asService(t=>t.query("select audit_record_copy_sweep('a')"));
 r=await c.asService(t=>t.query('select * from audit_list_copy_sweeps(1)')); assert.equal(r.rows[0].note_id,'b');
 await c.asService(t=>t.query("select audit_record_copy_sweep('b')"));
 r=await c.asService(t=>t.query('select * from audit_list_copy_sweeps(2)')); assert.equal(r.rows.length,2);
 } finally {await c.db.close()}
});
