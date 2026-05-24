import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';
import { parseAction, normalizeTargets, getSetVals } from './actionUtils.js';
import { normalizeHtml, applySelectedAccount, hydrateTargets } from './hydrationUtils.js';

const router = Router();

router.post('/auth/login', handleLogin);

router.post('/hydrate', async (req, res) => {
  const { template_name, page_id, page_title } = req.body;
  const email = req.session?.current_user_email;

  logger.info('[api] Request', {
    path: '/api/hydrate',
    body: req.body
  });

  try {
    const workflowName = template_name === 'wf_appbar' ? 'page-chrome' : 'hydrate-guide';
    const result = await callWorkflow(workflowName, {
      ...(template_name === 'wf_appbar'
        ? {
            ...(email ? { email } : {}),
            ...(page_id ? { page_id } : {}),
            ...(page_title ? { page_title } : {})
          }
        : {
            template_name,
            source: 'wf-server',
            format: 'html',
            ...(email ? { email } : {}),
            ...(page_id ? { page_id } : {}),
            ...(page_title ? { page_title } : {})
          })
    });
    const html = template_name === 'user_accounts_dd'
      ? applySelectedAccount(normalizeHtml(result), req.session?.account_id)
      : normalizeHtml(result);

    logger.info('[api] Response', {
      path: '/api/hydrate',
      success: true,
      status: 200,
      template_name,
      workflowName,
      htmlLength: html.length
    });

    res.type('html').send(html);
  } catch (err) {
    logger.error('[api] Response', {
      path: '/api/hydrate',
      success: false,
      status: 500,
      template_name,
      workflowName: template_name === 'wf_appbar' ? 'page-chrome' : 'hydrate-guide',
      error: err.message
    });
    res.status(500).type('text').send('Hydration failed');
  }
});

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

    if (actionName === 'redirect') {
      redirectUrl = action.payload?.url;
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
