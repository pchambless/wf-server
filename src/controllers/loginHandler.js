import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';
import { notifyActivity } from '../utils/activityNotify.js';
import { identityContextVals } from '../utils/contextGuard.js';

function getDefaultAccountId(result) {
  const accountVal = Array.isArray(result?.vals)
    ? result.vals.find(entry => entry?.param_name === 'account_id')?.param_val
    : null;

  return result?.user?.default_account_id
    ?? result?.default_account_id
    ?? result?.account_id
    ?? result?.context?.account_id
    ?? accountVal
    ?? null;
}

// Starts a signed-in session for a verified user: shared by password login and Google sign-in, so both leave the
// session and context in the same state.
export async function startSession(req, res, { email, user, defaultAccountId, path, activity }) {
  // These context values used to be written by the login workflow's own
  // L03-setvals node, which called this instance's /webhook/setvals by
  // absolute URL. That baked the hostname into the workflow, so every
  // dev -> prod import had to rewrite it. Setting them here keeps login
  // portable across n8n instances and drops an HTTP hop. The same list restores identity after a
  // browser-requested clear_all (task 845).
  const contextVals = identityContextVals(email, user, defaultAccountId);

  if (contextVals.length) {
    await callWorkflow('setvals', { email, vals: contextVals });
  }

  // The stored email, not the typed one: it is pasted into workflows on every page load (task 783).
  req.session.current_user_email = user.email || email;
  req.session.user = Object.keys(user).length ? user : { email };
  req.session.account_id = defaultAccountId;

  return req.session.save((err) => {
    if (err) {
      logger.error('[api] Response', { path, success: false, status: 500, reason: 'session_error' });
      return res.status(500).json({ success: false, message: 'Session error' });
    }

    notifyActivity(activity, email, req.get('user-agent'));
    logger.info('[api] Response', { path, success: true, status: 200, redirectTo: '/dashboard' });
    return res.json({ success: true, redirectTo: '/dashboard' });
  });
}

export async function handleLogin(req, res) {
  const { email, password } = req.body;

  logger.info('[api] Request', {
    path: '/api/auth/login',
    body: {
      email,
      password: password ? '[REDACTED]' : password
    }
  });

  if (!email || !password) {
    logger.warn('[api] Response', {
      path: '/api/auth/login',
      success: false,
      status: 400,
      reason: 'missing_credentials'
    });
    return res.status(400).json({ success: false, message: 'Email and password required' });
  }

  try {
    const result = await callWorkflow('login', { email, password });

    if (result?.success) {
      const user = result.user || {};
      const defaultAccountId = getDefaultAccountId(result);

      return startSession(req, res, { email, user, defaultAccountId, path: '/api/auth/login', activity: 'login' });
    }

    notifyActivity('login_failed', email, req.get('user-agent'));
    logger.warn('[api] Response', {
      path: '/api/auth/login',
      success: false,
      status: 401,
      reason: 'invalid_credentials'
    });
    return res.status(401).json({ success: false, message: result?.message || 'Invalid email or password' });
  } catch (err) {
    logger.error('[api] Response', {
      path: '/api/auth/login',
      success: false,
      status: 500,
      reason: 'login_service_unavailable',
      error: err.message
    });
    return res.status(500).json({ success: false, message: 'Login service unavailable' });
  }
}
