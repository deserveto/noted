// Deno Edge Runtime adapter for Supabase Edge Functions.
// Kept separate from `handler.ts` so every handler can also be unit-tested
// directly under Node.js v24 without Deno globals.

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'npm:@supabase/supabase-js@2';
import type { VerifyBearerToken } from './auth.ts';

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
};

export function getEnv(key: string, fallback = ''): string {
  return Deno.env.get(key)?.trim() ?? fallback;
}

export function createEdgeRuntimeDeps() {
  const supabaseUrl = getEnv('SUPABASE_URL');
  const anonKey = getEnv('SUPABASE_ANON_KEY');
  const serviceRoleKey = getEnv('SUPABASE_SERVICE_ROLE_KEY');

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const verifyToken: VerifyBearerToken = async (jwt: string) => {
    const { data, error } = await admin.auth.getUser(jwt);
    if (error || !data?.user?.id) return null;
    return {
      uid: data.user.id,
      email: (data.user.email ?? '').trim().toLowerCase(),
    };
  };

  const verifyPassword = async (email: string, password: string): Promise<boolean> => {
    if (!email || !password) return false;
    const ephemeral = createClient(supabaseUrl, anonKey || serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await ephemeral.auth.signInWithPassword({
      email,
      password,
    });
    return !error && Boolean(data?.user?.id);
  };

  return {
    admin: admin as any,
    verifyToken,
    verifyPassword,
    env: {
      aiBaseUrl: getEnv('AI_BASE_URL', 'https://openrouter.ai/api/v1'),
      aiModel: getEnv('AI_MODEL', 'openrouter/free'),
      aiApiKey: getEnv('AI_API_KEY'),
      resendApiKey: getEnv('RESEND_API_KEY'),
      emailFrom: getEnv('NOTED_EMAIL_FROM'),
      appUrl: getEnv('NOTED_APP_URL'),
      cronSecret: getEnv('CRON_SECRET'),
    },
  };
}

export function serveEdgeFunction(
  buildHandler: (deps: ReturnType<typeof createEdgeRuntimeDeps>) => (req: Request) => Promise<Response>,
) {
  Deno.serve(async (req: Request) => {
    const deps = createEdgeRuntimeDeps();
    return buildHandler(deps)(req);
  });
}
