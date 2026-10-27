import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseTestDb} from './pglite_supabase_harness.mjs';
const A='11111111-1111-4111-8111-111111111111';
async function seal(c) { const state=(await c.db.query('select audit_migration_state() as s')).rows[0].s; return c.asService(t=>t.query('select audit_seal_migration_rollback($1::jsonb)',[JSON.stringify(state)])); }
test('safe rollback refuses absent seal and removes only mapped notes after seal', async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.asService(t=>t.query('select audit_assert_migration_target_empty()'));
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('imported',$1,'one')",[A]));
 await c.asService(t=>t.query("insert into migration_id_mappings(entity_type,firebase_id,supabase_id,metadata) values('note','f','imported','{}')"));
 let result=await c.asService(t=>t.query('select audit_rollback_migration(true) as r')); assert.ok(result.rows[0].r.errors.length);
 await seal(c);
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('native',$1,'two')",[A]));
 result=await c.asService(t=>t.query('select audit_rollback_migration(false) as r')); assert.ok(result.rows[0].r.errors.length);
 assert.equal((await c.asService(t=>t.query('select count(*)::int as n from notes'))).rows[0].n,2);
 await c.asService(t=>t.query("delete from notes where note_id='native'"));
 result=await c.asService(t=>t.query('select audit_rollback_migration(false) as r')); assert.deepEqual(result.rows[0].r.errors,[]);
 assert.equal((await c.asService(t=>t.query('select count(*)::int as n from notes'))).rows[0].n,0);
 assert.equal((await c.asService(t=>t.query('select count(*)::int as n from profiles'))).rows[0].n,1);
 } finally {await c.db.close()}
});

test('safe rollback requires empty target and prevents resealing or client use', async()=>{
 const c=await createSupabaseTestDb(); try {
 assert.equal((await c.asService(t=>t.query('select audit_assert_migration_target_empty() as r'))).rows[0].r.empty,true);
 await assert.rejects(()=>c.asAnon(t=>t.query('select audit_assert_migration_target_empty()')));
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await assert.rejects(()=>c.asService(t=>t.query('select audit_assert_migration_target_empty()')));
 await c.asService(t=>t.query("insert into migration_id_mappings(entity_type,firebase_id,supabase_id) values('user','a',$1)",[A]));
 await seal(c);
 await assert.rejects(()=>c.asService(t=>t.query("select audit_seal_migration_rollback('{}'::jsonb)")));
 await assert.rejects(()=>c.asUser(A,t=>t.query('select audit_rollback_migration(false)')));
 } finally {await c.db.close()}
});
test('safe rollback rejects unrecorded note dependents even when present at seal', async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.asService(t=>t.query('select audit_assert_migration_target_empty()'));
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('imported',$1,'one')",[A]));
 await c.asService(t=>t.query("insert into migration_id_mappings(entity_type,firebase_id,supabase_id) values('note','f','imported')"));
 await c.asService(t=>t.query("insert into user_favorites(user_id,note_id) values($1,'imported')",[A]));
 await seal(c);
 const r=await c.asService(t=>t.query('select audit_rollback_migration(false) as r')); assert.match(r.rows[0].r.errors[0],/Unmapped dependent/);
 assert.equal((await c.asService(t=>t.query('select count(*)::int as n from notes'))).rows[0].n,1);
 } finally {await c.db.close()}
});
test('seal rejects a validated snapshot if a note changed before locking',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.asService(t=>t.query('select audit_assert_migration_target_empty()'));
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('n',$1,'validated')",[A]));
 await c.asService(t=>t.query("insert into migration_id_mappings(entity_type,firebase_id,supabase_id) values('note','f','n')"));
 const expected=(await c.db.query('select audit_migration_state() as s')).rows[0].s;
 await c.asUser(A,t=>t.query("update notes set title='attacker' where note_id='n'"));
 await assert.rejects(()=>c.asService(t=>t.query('select audit_seal_migration_rollback($1::jsonb)',[JSON.stringify(expected)])));
 assert.equal((await c.asService(t=>t.query('select audit_rollback_migration(true) as r'))).rows[0].r.errors.length,1);
 } finally {await c.db.close()}
});
