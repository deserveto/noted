import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseTestDb} from './pglite_supabase_harness.mjs';
const A='11111111-1111-4111-8111-111111111111';
test('bounded email batches rotate beyond 1000 deferred rows and wrap',async()=>{
 const c=await createSupabaseTestDb();try{
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("insert into notifications(id,user_id,type,title,created_at) select lpad(g::text,5,'0'),$1,'system','n',now() + g*interval '1 second' from generate_series(1,1001) g",[A]));
 for(let i=0;i<5;i++){const r=await c.asService(t=>t.query('select * from audit_take_email_batch(200)'));assert.equal(r.rows.length,200)}
 const last=await c.asService(t=>t.query('select * from audit_take_email_batch(200)'));assert.equal(last.rows[0].id,'01001');
 const first=await c.asService(t=>t.query('select * from audit_take_email_batch(200)'));assert.equal(first.rows[0].id,'00001');
 await assert.rejects(()=>c.asUser(A,t=>t.query('select * from audit_take_email_batch(1)')));
 }finally{await c.db.close()}
});
test('email cursor handles equal timestamps and enforces service-only bounds',async()=>{
 const c=await createSupabaseTestDb();try{
 await c.createAuthUser({id:A,email:'a@example.com',name:'A'});
 await c.asService(t=>t.query("insert into notifications(id,user_id,type,title,created_at) values('a',$1,'system','a',now()),('b',$1,'system','b',now()),('c',$1,'system','c',now())",[A]));
 for(const id of ['a','b','c','a']){const r=await c.asService(t=>t.query('select * from audit_take_email_batch(1)'));assert.equal(r.rows[0].id,id)}
 await assert.rejects(()=>c.asAnon(t=>t.query('select * from audit_take_email_batch(1)')));
 await assert.rejects(()=>c.asService(t=>t.query('select * from audit_take_email_batch(201)')));
 }finally{await c.db.close()}
});
