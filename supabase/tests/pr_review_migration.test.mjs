import test from 'node:test';
import assert from 'node:assert/strict';
import { exportFirebaseBundle } from '../../tools/migration/export_firebase.mjs';
import { createPGliteExecutor, createSupabaseAdminExecutor, importBundleToExecutor } from '../../tools/migration/import_supabase.mjs';
import { createPGliteReader, validateMigratedBundle } from '../../tools/migration/validate_migration.mjs';
import { createSupabaseTestDb } from './pglite_supabase_harness.mjs';

const bundle = () => ({auth:{users:[{uid:'alice', email:'alice@example.com', emailVerified:false, disabled:true}]}, firestore:{users:[{id:'alice'}]}, media:[]});

test('Firebase export reads the legacy connectionRequests collection', async () => {
  const requested = [];
  const app = {auth:()=>({listUsers:async()=>({users:[]})}), firestore:()=>({collection:name=>{
    requested.push(name);
    return {get:async()=>({docs:name === 'connectionRequests' ? [{id:'c1',data:()=>({fromUserId:'alice',toUserId:'bob',status:'accepted'})}] : []})};
  }})};
  const result = await exportFirebaseBundle(app,{includeMedia:false});
  assert.ok(requested.includes('connectionRequests'));
  assert.equal(result.firestore.connectionRequests[0].id, 'c1');
});

test('admin create and existing-user update preserve verification and ban state', async () => {
  const calls = [];
  let exists = false;
  const client = {auth:{admin:{createUser:async attrs=>{calls.push(['create',attrs]); return {error:exists?{message:'User already registered'}:null};},getUserById:async()=>({data:{user:{email_confirmed_at:null}},error:null}),updateUserById:async(id,attrs)=>{calls.push(['update',attrs]);return {error:null};}}}};
  const executor = createSupabaseAdminExecutor(client);
  const user = {id:'123',email:'alice@example.com',name:'Alice',emailVerified:false,disabled:true};
  await executor.upsertAuthUser(user);
  exists = true;
  await executor.upsertAuthUser({...user,emailVerified:true,disabled:false});
  assert.equal(calls[0][1].email_confirm,false);
  assert.equal(calls[0][1].ban_duration,'876000h');
  assert.equal(calls[2][1].email_confirm,true);
  assert.equal(calls[2][1].ban_duration,'none');
});

test('existing confirmed user cannot be silently downgraded to an unverified source', async () => {
  let updated = false;
  const client={auth:{admin:{createUser:async()=>({error:{message:'User already registered'}}),getUserById:async()=>({data:{user:{email_confirmed_at:'2020-01-01T00:00:00Z'}},error:null}),updateUserById:async()=>{updated=true;return {error:null};}}}};
  await assert.rejects(() => createSupabaseAdminExecutor(client).upsertAuthUser({id:'123',email:'a@example.com',name:'A',emailVerified:false,disabled:false}), /unconfirm/i);
  assert.equal(updated,false);
});

test('disabled source is banned even when existing confirmed status blocks import', async () => {
  const updates=[];
  const client={auth:{admin:{createUser:async()=>({error:{message:'User already registered'}}),getUserById:async()=>({data:{user:{email_confirmed_at:'2020-01-01T00:00:00Z'}},error:null}),updateUserById:async(_id,attrs)=>{updates.push(attrs);return {error:null};}}}};
  await assert.rejects(() => createSupabaseAdminExecutor(client).upsertAuthUser({id:'123',email:'a@example.com',name:'A',emailVerified:false,disabled:true}), /unconfirm/i);
  assert.deepEqual(updates,[{ban_duration:'876000h'}]);
});

test('auth status affects idempotency and parity detects target drift', async () => {
  const ctx = await createSupabaseTestDb();
  try {
    const e=createPGliteExecutor(ctx), b=bundle();
    await importBundleToExecutor(b,e);
    let result=await validateMigratedBundle(b,createPGliteReader(ctx));
    assert.equal(result.ok,true,JSON.stringify(result.errors));
    b.auth.users[0].emailVerified=true;
    b.auth.users[0].disabled=false;
    result=await validateMigratedBundle(b,createPGliteReader(ctx));
    assert.equal(result.ok,false);
    const rerun=await importBundleToExecutor(b,e);
    assert.equal(rerun.stats.inserted.user,1);
    assert.equal((await validateMigratedBundle(b,createPGliteReader(ctx))).ok,true);
  } finally { await ctx.db.close(); }
});
