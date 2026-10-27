import { AppError } from './cors.ts';

export interface AuthenticatedCaller {
  uid: string;
  email: string;
}

export type VerifyBearerToken = (jwt: string) => Promise<AuthenticatedCaller | null>;

export async function requireAuthenticatedUser(
  req: Request,
  verifyToken: VerifyBearerToken,
): Promise<AuthenticatedCaller> {
  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization') ?? '';
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match || !match[1]?.trim()) {
    throw new AppError('unauthenticated', 'Sign in required.', 401);
  }

  const caller = await verifyToken(match[1].trim());
  if (!caller || !caller.uid) {
    throw new AppError('unauthenticated', 'Invalid or expired session.', 401);
  }
  return caller;
}

export function requireCronSecret(req: Request, expectedSecret: string | undefined): void {
  const expected = expectedSecret?.trim() ?? '';
  const received = (req.headers.get('x-cron-secret') ?? '').trim();
  if (!expected || !received || expected.length !== received.length) {
    throw new AppError('unauthenticated', 'Valid cron secret required.', 401);
  }
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ received.charCodeAt(i);
  }
  if (diff !== 0) {
    throw new AppError('unauthenticated', 'Valid cron secret required.', 401);
  }
}
