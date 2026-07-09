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
      const defaultAccountId = getDefaultAccountId(result);

      if (defaultAccountId !== null && defaultAccountId !== undefined && defaultAccountId !== '') {
        await callWorkflow('setvals', {
          email,
          vals: [{ param_name: 'account_id', param_val: String(defaultAccountId) }]
        });
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
