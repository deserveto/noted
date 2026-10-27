import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createSupabaseTestDb } from './pglite_supabase_harness.mjs';
import { exportFirebaseBundle, loadBundleFromDir } from '../../tools/migration/export_firebase.mjs';
import { createPGliteExecutor, importBundleToExecutor } from '../../tools/migration/import_supabase.mjs';
import { createPGliteReader, validateMigratedBundle } from '../../tools/migration/validate_migration.mjs';
import { rollbackMigratedEntities } from '../../tools/migration/rollback_supabase.mjs';
const uid='legacy-user';
const bundle=()=>({auth:{users:[{uid,email:'owner@example.com',metadata:{creationTime:'2020-01-01T00:00:00Z'}}]},firestore:{users:[{id:uid}],userSettings:[{userId:uid,theme:'dark',requests:'nobody',updatedAt:'2020-01-01T00:00:00Z'}],notes:[{id:'n1',userId:uid,title:'Original',content:'original content',createdAt:'2020-01-01T00:00:00Z',updatedAt:'2020-01-01T00:00:00Z'}],aiRequests:[{userId:uid,requestId:'r1',status:'completed',cancelled:false,createdAt:'2020-01-01T00:00:00Z',updatedAt:'2020-01-01T00:00:00Z'}]},media:[]});
test('flat preferences and AI requests survive import',async()=>{const ctx=await createSupabaseTestDb();try{await importBundleToExecutor(bundle(),createPGliteExecutor(ctx));const s=await ctx.db.query('select preferences from public.user_settings');assert.deepEqual(s.rows[0].preferences,{theme:'dark',requests:'nobody'});const a=await ctx.db.query('select request_id,status from public.ai_requests');assert.deepEqual(a.rows,[{request_id:'r1',status:'completed'}]);}finally{await ctx.db.close();}});
test('validation detects changed note content',async()=>{const ctx=await createSupabaseTestDb();try{const b=bundle();await importBundleToExecutor(b,createPGliteExecutor(ctx));await ctx.db.query("update public.notes set content='DESTROYED' where note_id='n1'");assert.equal((await validateMigratedBundle(b,createPGliteReader(ctx))).ok,false);}finally{await ctx.db.close();}});
test('rollback refuses post-cutover notes before deletion',async()=>{const ctx=await createSupabaseTestDb();try{const e=createPGliteExecutor(ctx);await importBundleToExecutor(bundle(),e);await ctx.db.query("insert into public.notes(note_id,user_id,title) select 'native',id,'native' from public.profiles limit 1");assert.ok((await rollbackMigratedEntities(e,{dryRun:true})).errors.length);await assert.rejects(()=>rollbackMigratedEntities(e),/rollback|unsafe|blocked/i);const r=await ctx.db.query('select note_id from public.notes order by note_id');assert.deepEqual(r.rows.map(x=>x.note_id),['n1','native']);}finally{await ctx.db.close();}});
test('bundle loading rejects absent files and checksums',async()=>{const dir=await fs.mkdtemp(path.join(os.tmpdir(),'noted-bundle-'));try{await fs.writeFile(path.join(dir,'manifest.json'),JSON.stringify({checksums:{}}));await fs.writeFile(path.join(dir,'users.json'),'{"users":[]}');await assert.rejects(()=>loadBundleFromDir(dir));}finally{await fs.rm(dir,{recursive:true,force:true});}});
test('export fails on denied user subcollection reads',async()=>{const doc={id:uid,exists:true,data:()=>({}),ref:{collection:()=>({doc:()=>({get:async()=>{throw Error('PERMISSION_DENIED')}}),get:async()=>{throw Error('PERMISSION_DENIED')}})}};const app={auth:()=>({listUsers:async()=>({users:[]})}),firestore:()=>({collection:name=>({get:async()=>({docs:name==='users'?[doc]:[]})})})};await assert.rejects(()=>exportFirebaseBundle(app,{includeMedia:false}),e=>e.blockerReport?.status==='BLOCKED');});
test('bundle detects modified bytes and preserves AI request export',async()=>{const dir=await fs.mkdtemp(path.join(os.tmpdir(),'noted-export-'));try{const doc={id:uid,exists:true,data:()=>({}),ref:{collection:name=>({doc:id=>({get:async()=>({exists:name==='settings'&&id==='preferences',data:()=>({theme:'dark'})})}),get:async()=>({docs:name==='aiRequests'?[{id:'r1',data:()=>({status:'completed'})}]:[]})})}};const app={auth:()=>({listUsers:async()=>({users:[]})}),firestore:()=>({collection:name=>({get:async()=>({docs:name==='users'?[doc]:[]})})})};await exportFirebaseBundle(app,{outDir:dir,includeMedia:false});const loaded=await loadBundleFromDir(dir);assert.equal(loaded.firestore.userSettings[0].theme,'dark');assert.equal(loaded.firestore.aiRequests[0].requestId,'r1');await fs.writeFile(path.join(dir,'firestore','notes.json'),'[] ');await assert.rejects(()=>loadBundleFromDir(dir),/checksum/i);}finally{await fs.rm(dir,{recursive:true,force:true});}});
test('validation rejects changed AI citations and stored media bytes',async()=>{const ctx=await createSupabaseTestDb();try{const b=bundle();b.firestore.aiChats=[{userId:uid,chatId:'chat',createdAt:'2020-01-01T00:00:00Z'}];b.firestore.aiMessages=[{id:'message',userId:uid,chatId:'chat',role:'ai',sources:[{noteId:'n1',title:'Original'}],createdAt:'2020-01-01T00:00:00Z'}];b.media=[{sourcePath:'users/legacy-user/avatar.png',data:Buffer.from('avatar'),contentType:'image/png'}];await importBundleToExecutor(b,createPGliteExecutor(ctx));await ctx.db.query(`update public.ai_messages set sources='[{"noteId":"n1","title":"Changed"}]'::jsonb where id='message'`);await ctx.db.query(`update storage.objects set metadata=metadata || '{"sha256":"bad"}'::jsonb`);const result=await validateMigratedBundle(b,createPGliteReader(ctx));assert.equal(result.ok,false);assert.match(result.errors.join(' '),/sources/);assert.match(result.errors.join(' '),/checksum/);}finally{await ctx.db.close();}});
test('sealed untouched import permits database rollback and retains identity',async()=>{const ctx=await createSupabaseTestDb();try{const e=createPGliteExecutor(ctx);await importBundleToExecutor(bundle(),e,{sealRollback:true});const preview=await rollbackMigratedEntities(e,{dryRun:true});assert.deepEqual(preview.errors,[]);assert.ok(preview.retained.authUsers);const result=await rollbackMigratedEntities(e);assert.deepEqual(result.errors,[]);assert.equal((await ctx.db.query('select count(*)::int c from public.notes')).rows[0].c,0);assert.equal((await ctx.db.query('select count(*)::int c from auth.users')).rows[0].c,1);}finally{await ctx.db.close();}});
test('sealing refuses a non-empty target before overwriting any row',async()=>{const ctx=await createSupabaseTestDb();try{const e=createPGliteExecutor(ctx);await ctx.createAuthUser({id:'99999999-9999-4999-8999-999999999999',email:'native@example.com',name:'Native'});await assert.rejects(()=>importBundleToExecutor(bundle(),e,{sealRollback:true}),/empty|existing|blocked/i);assert.equal((await ctx.db.query('select count(*)::int c from public.notes')).rows[0].c,0);assert.equal((await ctx.db.query('select count(*)::int c from auth.users')).rows[0].c,1);}finally{await ctx.db.close();}});
test('sealed rollback refuses edits and native cascade dependencies before deleting',async()=>{const ctx=await createSupabaseTestDb();try{const e=createPGliteExecutor(ctx);await importBundleToExecutor(bundle(),e,{sealRollback:true});await ctx.db.query("insert into public.notes(note_id,user_id,title) select 'native',id,'native' from public.profiles limit 1");const preview=await rollbackMigratedEntities(e,{dryRun:true});assert.ok(preview.errors.length);await assert.rejects(()=>rollbackMigratedEntities(e),/blocked|changed|unsafe/i);assert.equal((await ctx.db.query('select count(*)::int c from public.notes')).rows[0].c,2);}finally{await ctx.db.close();}});
test('sealing rejects a write after the validated snapshot', async () => {
  const ctx = await createSupabaseTestDb();
  try {
    const executor = createPGliteExecutor(ctx), query = executor.query.bind(executor);
    executor.query = async (sql, params) => {
      if (sql.includes('audit_seal_migration_rollback')) await ctx.db.query("update public.notes set title='late edit' where note_id='n1'");
      return query(sql, params);
    };
    await assert.rejects(() => importBundleToExecutor(bundle(), executor, {sealRollback:true}), /snapshot|changed|match/i);
    assert.ok((await rollbackMigratedEntities(executor, {dryRun:true})).errors.length);
  } finally { await ctx.db.close(); }
});
test('sealing rejects unmapped data already present in snapshot', async () => {
  const ctx = await createSupabaseTestDb();
  try {
    const executor = createPGliteExecutor(ctx), query = executor.query.bind(executor);
    executor.query = async (sql, params) => {
      if (sql.includes('audit_get_migration_rollback_state')) await ctx.db.query("insert into public.notes(note_id,user_id,title) select 'native',id,'native' from public.profiles limit 1");
      return query(sql, params);
    };
    await assert.rejects(() => importBundleToExecutor(bundle(), executor, {sealRollback:true}), /extra|count|unexpected|validation/i);
    assert.ok((await rollbackMigratedEntities(executor, {dryRun:true})).errors.length);
  } finally { await ctx.db.close(); }
});
test('sealing rejects changed imported content already in snapshot', async () => {
  const ctx = await createSupabaseTestDb();
  try {
    const executor = createPGliteExecutor(ctx), query = executor.query.bind(executor);
    executor.query = async (sql, params) => {
      if (sql.includes('audit_get_migration_rollback_state')) await ctx.db.query("update public.notes set content='changed before snapshot' where note_id='n1'");
      return query(sql, params);
    };
    await assert.rejects(() => importBundleToExecutor(bundle(), executor, {sealRollback:true}), /validation|content/i);
    assert.ok((await rollbackMigratedEntities(executor, {dryRun:true})).errors.length);
  } finally { await ctx.db.close(); }
});
test('sealing rejects storage objects added before the snapshot', async () => {
  const ctx = await createSupabaseTestDb();
  try {
    const executor = createPGliteExecutor(ctx), query = executor.query.bind(executor);
    executor.query = async (sql, params) => {
      if (sql.includes('audit_get_migration_rollback_state')) await ctx.db.query("insert into storage.objects(bucket_id,name) values ('avatars','native.png')");
      return query(sql, params);
    };
    await assert.rejects(() => importBundleToExecutor(bundle(), executor, {sealRollback:true}), /unexpected|storage/i);
    assert.ok((await rollbackMigratedEntities(executor, {dryRun:true})).errors.length);
  } finally { await ctx.db.close(); }
});
test('sealed import accepts matching media identity and checksum', async () => {
  const ctx = await createSupabaseTestDb();
  try {
    const b = bundle();
    b.media = [{sourcePath:'users/legacy-user/avatar.png',data:Buffer.from('avatar'),contentType:'image/png'}];
    const executor = createPGliteExecutor(ctx);
    await importBundleToExecutor(b, executor, {sealRollback:true});
    const preview = await rollbackMigratedEntities(executor, {dryRun:true});
    assert.deepEqual(preview.errors, []);
    assert.equal(preview.retained.media, 1);
  } finally { await ctx.db.close(); }
});
