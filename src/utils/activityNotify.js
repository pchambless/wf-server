import logger from './logger.js';

// Posts "who logged in / out" to a Slack incoming webhook. Does nothing unless SLACK_ACTIVITY_WEBHOOK is set,
// so local runs stay quiet. Fire-and-forget: callers must not await it, and a Slack failure never reaches the user.
// Env vars are read per call, not at import, so the dotenv load order (src/env.js) can't bite.
const ICONS = { login: ':large_green_circle:', logout: ':white_circle:', login_failed: ':warning:' };
const WORDS = { login: 'logged in', logout: 'logged out', login_failed: 'failed login' };

export function notifyActivity(event, email) {
  const url = process.env.SLACK_ACTIVITY_WEBHOOK;
  if (!url || !email) return;
  const IGNORE = (process.env.SLACK_ACTIVITY_IGNORE || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  if (IGNORE.includes(String(email).toLowerCase())) return;

  const text = `${ICONS[event] || ':grey_question:'} ${email} ${WORDS[event] || event} [${process.env.APP_ENV || 'dev'}]`;
  fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
    signal: AbortSignal.timeout(3000)
  }).then(res => {
    if (!res.ok) logger.warn('[activity] Slack rejected the post', { status: res.status });
  }).catch(err => logger.warn('[activity] Slack post failed', { error: err.message }));
}
