import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  createPGliteExecutor,
  createSupabaseAdminExecutor,
  selectAllPostgrestRows,
} from './import_supabase.mjs';

export function parseArgs(argv = process.argv.slice(2)) {
  const args = {
    dryRun: false,
    confirmRollback: false,
    supabaseUrl: process.env.SUPABASE_URL || null,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || null,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--dry-run') {
      args.dryRun = true;
    } else if (arg === '--confirm-rollback') {
      args.confirmRollback = true;
    } else if (arg === '--supabase-url' && i + 1 < argv.length) {
      args.supabaseUrl = argv[++i];
    } else if (arg === '--service-role-key' && i + 1 < argv.length) {
      args.serviceRoleKey = argv[++i];
    }
  }

  return args;
}

/**
 * Programmatically rolls back migrated entities recorded in public.migration_id_mappings.
 * Executes deletions in safe foreign-key order without touching native non-migrated data.
 */
export async function rollbackMigratedEntities(rawExecutor, { dryRun = false } = {}) {
  const executor = rawExecutor.isPGlite || rawExecutor.isSupabaseClient ? rawExecutor : createPGliteExecutor(rawExecutor);
  let result;
  try {
    if (executor.isPGlite) {
      const response = await executor.query('SELECT public.audit_rollback_migration($1) AS result', [dryRun]);
      result = response.rows[0].result;
    } else {
      const response = await executor.client.rpc('audit_rollback_migration', {p_dry_run: dryRun});
      if (response.error) throw response.error;
      result = response.data;
    }
  } catch (err) {
    if (dryRun) return {dryRun: true, errors: [`Rollback blocked: ${err.message}`]};
    throw new Error(`Rollback blocked: ${err.message}`);
  }
  if (!result || !Array.isArray(result.errors)) throw new Error('Rollback blocked: invalid safety response');
  if (!dryRun && result.errors.length) throw new Error(`Rollback blocked: ${result.errors.join('; ')}`);
  return result;
}

/**
 * CLI execution entrypoint
 */
async function runCli() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.dryRun && !args.confirmRollback) {
    console.error(
      'ROLLBACK BLOCKED: Missing confirmation flag.\n' +
        'To preview deletions safely, pass: --dry-run\n' +
        'To execute live deletion of migrated entities, pass: --confirm-rollback --supabase-url <url> --service-role-key <key>',
    );
    process.exit(1);
  }

  if (!args.supabaseUrl || !args.serviceRoleKey) {
    console.error('Error: --supabase-url and --service-role-key are required for rollback.');
    process.exit(1);
  }

  const { createClient } = await import('@supabase/supabase-js');
  const supabase = createClient(args.supabaseUrl, args.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const executor = createSupabaseAdminExecutor(supabase);

  console.log(`Executing rollback (dryRun: ${args.dryRun})...`);
  const result = await rollbackMigratedEntities(executor, { dryRun: args.dryRun });

  console.log('Rollback Summary:');
  console.log(JSON.stringify(result, null, 2));
  if (result.errors.length) process.exitCode = 1;
}

const currentFileUrl = import.meta.url;
const executedFileUrl = pathToFileURL(path.resolve(process.argv[1] || '')).href;
if (currentFileUrl === executedFileUrl) {
  runCli().catch((err) => {
    console.error('Fatal rollback error:', err);
    process.exit(1);
  });
}
