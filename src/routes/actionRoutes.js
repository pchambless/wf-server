import { Router } from 'express';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';
import { notifyActivity } from '../utils/activityNotify.js';
import { parseAction, normalizeTargets, getSetVals } from './actionUtils.js';
import { hydrateTargets } from './hydrationUtils.js';

const router = Router();

router.post('/actions', async (req, res) => {
  const email = req.session?.current_user_email;
  const action = parseAction(req.body.action);
  const selectedValue = req.body.value ?? '';

  logger.info('[api] Request', {
    path: '/api/actions',
    body: {
      component_id: req.body.component_id,
      trigger: action?.trigger,
      value: selectedValue,
      targets: action?.targets
    }
  });

  // Log Out works with or without a live session: with none there is nothing to end, just go to the login page.
  if (!email && String(action?.action || '').toLowerCase() === 'logout') {
    return res.json({ success: true, redirectUrl: '/login' });
  }

  if (!email) {
    return res.status(401).json({ success: false, message: 'Authentication required' });
  }

  if (!action) {
    return res.status(400).json({ success: false, message: 'Action payload required' });
  }

  try {
    const actionName = String(action.action || '').toLowerCase();
    let targets = normalizeTargets(action.targets);
    let redirectUrl = null;

    // Log Out (task 697): clear every context value (as task 181 intended), then END the server session
    // and drop the cookie. Before this, Log Out only cleared a few keys and the 24-hour session stayed valid.
    if (actionName === 'logout') {
      await callWorkflow('clearvals', { email, params: [], clear_all: true });
      return req.session.destroy((err) => {
        if (err) {
          logger.error('[api] Response', { path: '/api/actions', success: false, status: 500, error: err.message });
          return res.status(500).json({ success: false, message: 'Log out failed' });
        }
        res.clearCookie('connect.sid');
        notifyActivity('logout', email);
        logger.info('[api] Response', { path: '/api/actions', success: true, status: 200, redirectUrl: '/login' });
        return res.json({ success: true, redirectUrl: '/login' });
      });
    }

    if (actionName === 'setvals') {
      const vals = getSetVals(action, selectedValue);
      if (vals.length > 0) {
        await callWorkflow('setvals', { email, vals });

        const accountValue = vals.find(({ param_name }) => param_name === 'account_id')?.param_val;
        if (accountValue) {
          req.session.account_id = accountValue;
        }
      }
    }

    if (actionName === 'clearvals') {
      const params = action.values || action.context_keys || [];
      const clearAll = action.clear_all || false;
      if (clearAll || params.length > 0) {
        await callWorkflow('clearvals', { email, params, clear_all: clearAll });
      }
    }

    if (actionName === 'redirect') {
      redirectUrl = action.redirectUrl || action.payload?.url;
    }

    if (redirectUrl) {
      logger.info('[api] Response', {
        path: '/api/actions',
        success: true,
        status: 200,
        redirectUrl
      });
      return res.json({ success: true, redirectUrl });
    }

    const updates = await hydrateTargets(email, targets, action.swap_mode);

    logger.info('[api] Response', {
      path: '/api/actions',
      success: true,
      status: 200,
      updatedTargets: updates.map(update => update.target)
    });

    return res.json({ success: true, updates });
  } catch (err) {
    logger.error('[api] Response', {
      path: '/api/actions',
      success: false,
      status: 500,
      error: err.message
    });
    return res.status(500).json({ success: false, message: 'Action execution failed' });
  }
});

export default router;
