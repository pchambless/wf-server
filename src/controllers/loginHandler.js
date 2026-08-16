import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

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

      // These context values used to be written by the login workflow's own
      // L03-setvals node, which called this instance's /webhook/setvals by
      // absolute URL. That baked the hostname into the workflow, so every
      // dev -> prod import had to rewrite it. Setting them here keeps login
      // portable across n8n instances and drops an HTTP hop.
      const contextVals = [
        { param_name: 'userEmail', param_val: email },
        { param_name: 'userID', param_val: user.user_id },
        { param_name: 'account_id', param_val: defaultAccountId },
        { param_name: 'firstName', param_val: user.first_name },
        { param_name: 'lastName', param_val: user.last_name },
        { param_name: 'role_id', param_val: user.role_id }
      ]
        .filter(v => v.param_val !== null && v.param_val !== undefined && v.param_val !== '')
        .map(v => ({ param_name: v.param_name, param_val: String(v.param_val) }));

      if (contextVals.length) {
        await callWorkflow('setvals', { email, vals: contextVals });
      }

      req.session.current_user_email = email;
      req.session.user = result.user || { email };
      req.session.account_id = defaultAccountId;

      return req.session.save((err) => {
        if (err) {
          logger.error('[api] Response', {
            path: '/api/auth/login',
            success: false,
            status: 500,
            reason: 'session_error'
          });
          return res.status(500).json({ success: false, message: 'Session error' });
        }

        logger.info('[api] Response', {
          path: '/api/auth/login',
          success: true,
          status: 200,
          redirectTo: '/wf-dashboard'
        });
        return res.json({ success: true, redirectTo: '/wf-dashboard' });
      });
    }

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
