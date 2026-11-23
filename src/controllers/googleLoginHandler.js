import { callWorkflow } from '../utils/n8nClient.js';
import { escSqlString } from '../utils/sqlEscape.js';
import { isPlainEmail } from '../utils/emailCheck.js';
import { verifyGoogleIdToken } from '../utils/googleIdToken.js';
import { notifyActivity } from '../utils/activityNotify.js';
import logger from '../utils/logger.js';
import { startSession } from './loginHandler.js';

const PATH = '/api/auth/google';

// "Sign in with Google": an alternative to the password for an existing user, never a way to create one. Google's ID
// token proves who the person is; the verified email is matched (case-insensitively) to a live WhatsFresh user, and
// that user gets the same session a password login gives. No Google token is kept. Error statuses avoid 401 so the
// page script's dead-session redirect doesn't swallow the message.
export async function handleGoogleLogin(req, res) {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  if (!clientId) return res.status(404).json({ success: false, message: 'Google sign-in is not enabled' });

  let claims;
  try {
    claims = await verifyGoogleIdToken(req.body?.credential, clientId);
  } catch (err) {
    logger.warn('[api] Response', { path: PATH, success: false, status: 400, reason: 'invalid_google_token', error: err.message });
    return res.status(400).json({ success: false, message: 'Google sign-in failed. Please try again or use your password.' });
  }

  const email = String(claims.email).trim();
  logger.info('[api] Request', { path: PATH, email });
  if (!isPlainEmail(email)) {
    return res.status(400).json({ success: false, message: 'That Google email address cannot be used here.' });
  }

  try {
    // Same user fields the password login returns, and the same last_login stamp its workflow sets.
    const result = await callWorkflow('server-query', {
      query: `UPDATE whatsfresh.users SET last_login = now()
        WHERE id = (SELECT id FROM whatsfresh.users
                    WHERE lower(email::text) = lower(${escSqlString(email)}) AND deleted_at IS NULL
                    ORDER BY id LIMIT 1)
        RETURNING email::text AS email, id AS user_id, first_name::text AS first_name, last_name::text AS last_name,
                  role::int AS role_id, default_account_id::int AS default_account_id`,
      params: {},
      source: 'google-login'
    });
    const user = Array.isArray(result) ? result[0] : result;

    if (!user?.user_id) {
      notifyActivity('login_failed', email, req.get('user-agent'));
      logger.warn('[api] Response', { path: PATH, success: false, status: 403, reason: 'no_matching_user', email });
      return res.status(403).json({
        success: false,
        message: `No WhatsFresh account uses ${email}. Sign in with your password, or ask your account owner to add this email.`
      });
    }

    return startSession(req, res, {
      email: user.email, user, defaultAccountId: user.default_account_id, path: PATH, activity: 'login_google'
    });
  } catch (err) {
    logger.error('[api] Response', { path: PATH, success: false, status: 500, reason: 'login_service_unavailable', error: err.message });
    return res.status(500).json({ success: false, message: 'Login service unavailable' });
  }
}
