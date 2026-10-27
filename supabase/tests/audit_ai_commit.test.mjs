import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseTestDb} from './pglite_supabase_harness.mjs';
const A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222';
test('AI exchange authorizes dependencies atomically and records provenance',async()=>{
 const c=await createSupabaseTestDb(); try {
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'}); await c.createAuthUser({id:B,email:'b@example.com',name:'B'});
 await c.asUser(A,t=>t.query("insert into notes(note_id,user_id,title) values('n',$1,'private')",[A]));
 await c.asService(t=>t.query("update notes set live_member_ids=array[$1]::uuid[],live_roles=jsonb_build_object($1::text,'view') where note_id='n'",[B]));
 await c.asService(t=>t.query("insert into ai_requests(user_id,request_id,status) values($1,'r','running'),($1,'r2','running')",[B]));
 const commit=(requestId='r')=>c.asService(t=>t.query("select audit_commit_ai_exchange($1,$2,array['n'],'chat','title','{}','prompt','{\"blocks\":[],\"sources\":[\"n\"],\"intent\":\"answer\"}',true) as r",[B,requestId]));
 const r=await commit(); assert.ok(r.rows[0].r.messageId);
 const messages=await c.asService(t=>t.query("select context_dependencies from ai_messages order by created_at")); assert.deepEqual(messages.rows.map(x=>x.context_dependencies),[['n'],['n']]);
 await c.asService(t=>t.query("update notes set live_member_ids='{}',live_roles='{}' where note_id='n'"));
 await assert.rejects(()=>commit('r2'));
 assert.equal((await c.asService(t=>t.query('select count(*)::int as n from ai_messages'))).rows[0].n,2);
 await assert.rejects(()=>c.asService(t=>t.query("select audit_commit_ai_exchange($1,'r2',array['n'],'chat','title','{}','prompt','{\"blocks\":[],\"sources\":[],\"intent\":\"answer\"}',false)",[B])));
 } finally {await c.db.close()}
});
