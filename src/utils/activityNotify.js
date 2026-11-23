import logger from './logger.js';

// Posts "who logged in / out" to a Slack incoming webhook. Does nothing unless SLACK_ACTIVITY_WEBHOOK is set,
// so local runs stay quiet. Fire-and-forget: callers must not await it, and a Slack failure never reaches the user.
// Env vars are read per call, not at import, so the dotenv load order (src/env.js) can't bite.
const ICONS = { login: ':large_green_circle:', login_google: ':large_green_circle:', logout: ':white_circle:', login_failed: ':warning:' };
const WORDS = { login: 'logged in', login_google: 'logged in with Google', logout: 'logged out', login_failed: 'failed login' };

// Slack hides the time on messages posted close together, so the time goes in the text (Central, like the reports).
const CLOCK = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Chicago', hour: 'numeric', minute: '2-digit' });

// Non-browser clients (scripts, AI agents, curl) get a robot line naming what they called themselves, so a scripted
// login is visible (task 718: a partner's Grok skill signs in with the partner's own password). Every mainstream browser
// sends "Mozilla/5.0 ..."; headless browsers and script libraries are flagged even if they imitate it. The User-Agent is
// caller-controlled text: it is trimmed and stripped of Slack markup characters before it is posted.
export function describeClient(userAgent) {
  const ua = String(userAgent || '').trim();
  const automated = !ua || !/^Mozilla\/5\.0 /.test(ua) || /headless|python|curl|wget|httpclient|okhttp|axios|node-fetch|undici|bot\b|spider|skill/i.test(ua);
  if (!automated) return '';
  const shown = ua ? ua.replace(/[<>&`*_~|\n\r]/g, '').slice(0, 100) : 'no User-Agent';
  return `\n:robot_face: not a browser: \`${shown}\``;
}

export function notifyActivity(event, email, userAgent) {
  const url = process.env.SLACK_ACTIVITY_WEBHOOK;
  if (!url || !email) return;
  const IGNORE = (process.env.SLACK_ACTIVITY_IGNORE || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  if (IGNORE.includes(String(email).toLowerCase())) return;

  const text = `${ICONS[event] || ':grey_question:'} ${email} ${WORDS[event] || event} [${process.env.APP_ENV || 'dev'}] ${CLOCK.format(new Date())} CT`
    + describeClient(userAgent);
  fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
    signal: AbortSignal.timeout(3000)
  }).then(res => {
    if (!res.ok) logger.warn('[activity] Slack rejected the post', { status: res.status });
  }).catch(err => logger.warn('[activity] Slack post failed', { error: err.message }));
}
