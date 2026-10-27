import { AppError } from './cors.ts';
import { emailAllowed, escapeHtml } from './policy.ts';

export interface EmailEnv {
  resendApiKey?: string;
  emailFrom?: string;
  appUrl?: string;
}

export async function sendResendEmail(params: {
  fetchImpl?: typeof fetch;
  env: EmailEnv;
  to: string;
  subject: string;
  html: string;
  idempotencyKey?: string;
  requireConfigured?: boolean;
}): Promise<{ sent: boolean; reason?: string }> {
  const fetchFn = params.fetchImpl ?? fetch;
  const apiKey = params.env.resendApiKey?.trim() ?? '';
  const from = params.env.emailFrom?.trim() ?? '';

  if (!apiKey || !from) {
    if (params.requireConfigured) {
      throw new AppError(
        'failed-precondition',
        'Email invitations are not configured yet.',
      );
    }
    return { sent: false, reason: 'unconfigured' };
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
  if (params.idempotencyKey) {
    headers['Idempotency-Key'] = params.idempotencyKey;
  }

  const res = await fetchFn('https://api.resend.com/emails', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      from,
      to: [params.to],
      subject: params.subject,
      html: params.html,
    }),
  });

  if (!res.ok) {
    throw new AppError('unavailable', 'Email provider rejected the message.');
  }

  return { sent: true };
}

export function buildNotificationEmailHtml(params: {
  title: string;
  body: string;
  appUrl?: string;
  noteId?: string | null;
}): string {
  const baseUrl = params.appUrl?.trim().replace(/\/+$/, '') ?? '';
  const hasHttps = baseUrl.startsWith('https://');
  const openUrl = hasHttps
    ? params.noteId
      ? `${baseUrl}/notes/${encodeURIComponent(params.noteId)}`
      : baseUrl
    : '';

  return (
    `<div style="font-family:Georgia,serif;color:#1C1917;line-height:1.6;max-width:480px">` +
    `<p style="font-size:18px;margin:0 0 8px"><strong>${escapeHtml(params.title)}</strong></p>` +
    `<p style="color:#57534E;margin:0 0 18px">${escapeHtml(params.body)}</p>` +
    (openUrl
      ? `<p><a href="${escapeHtml(openUrl)}" style="color:#2D6A4F;font-weight:600">Open Noted</a></p>`
      : '') +
    `</div>`
  );
}

export function isNotificationEmailEnabled(
  type: string,
  preferences: Record<string, unknown> = {},
  timezoneOffsetMinutes = 0,
  now: Date = new Date(),
): boolean {
  const prefKey =
    type === 'request'
      ? 'nRequests'
      : type === 'copy'
        ? 'nCopies'
        : type === 'live'
          ? 'nLive'
          : null;
  if (!prefKey) return false;
  if (preferences[prefKey] === false) return false;
  return emailAllowed(preferences, timezoneOffsetMinutes, now);
}
