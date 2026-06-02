import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';
import { parseAction, normalizeTargets, getSetVals } from './actionUtils.js';
import { hydrateTargets } from './hydrationUtils.js';
import hydrateRoutes from './hydrateRoutes.js';

const router = Router();

router.post('/auth/login', handleLogin);

// Hydration routes (/hydrate, /report)
router.use(hydrateRoutes);

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
      const keys = action.context_keys || [];
      if (keys.length > 0) {
        await callWorkflow('clearvals', { email, keys });
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
