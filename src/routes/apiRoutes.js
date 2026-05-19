import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

const router = Router();

function normalizeHtml(result) {
  return typeof result === 'string' ? result : result?.html || result?.[0]?.html || '';
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function applySelectedAccount(html, accountId) {
  if (!html || accountId === null || accountId === undefined || accountId === '') {
    return html;
  }

  if (/\sselected(?:=|\s|>)/i.test(html)) {
    return html;
  }

  const value = escapeRegExp(String(accountId));
  const optionPattern = new RegExp(`(<option\\b[^>]*value=["'])${value}(["'][^>]*)(>)`, 'i');

  if (!optionPattern.test(html)) {
    return html;
  }

  return html.replace(optionPattern, '$1' + String(accountId) + '$2 selected$3');
}

function parseAction(action) {
  if (!action) return null;

  if (typeof action === 'string') {
    try {
      return JSON.parse(action);
    } catch {
      return null;
    }
  }

  return action;
}

function normalizeTargets(targets) {
  if (Array.isArray(targets)) return targets.filter(Boolean);
  if (typeof targets !== 'string' || targets.trim() === '') return [];

  try {
    const parsed = JSON.parse(targets);
    return Array.isArray(parsed) ? parsed.filter(Boolean) : [];
  } catch {
    return [targets];
  }
}

function resolveActionValue(value, selectedValue) {
  if (typeof value === 'string') {
    return value
      .replaceAll('{{value}}', selectedValue ?? '')
      .replaceAll('{{selected_value}}', selectedValue ?? '');
  }

  if (Array.isArray(value)) {
    return value.map(item => resolveActionValue(item, selectedValue));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entryValue]) => [key, resolveActionValue(entryValue, selectedValue)])
    );
  }

  return value;
}

function getSetVals(step, selectedValue) {
  const vals = step?.payload?.vals || step?.vals || step?.values;
  if (!vals || typeof vals !== 'object' || Array.isArray(vals)) return [];

  return Object.entries(vals)
    .map(([param_name, param_val]) => ({
      param_name,
      param_val: String(resolveActionValue(param_val, selectedValue) ?? '')
    }))
    .filter(({ param_val }) => param_val !== '');
}

async function hydrateTargets(email, targets, swapMode) {
  if (targets.length === 0) return [];

  const structure = await callWorkflow('page-structure', { email });
  const pageInfo = structure?.pageInfo;
  const components = Array.isArray(structure?.components) ? structure.components : [];
  const componentByName = new Map(components.map(component => [component.comp_name, component]));
  const updates = [];

  for (const target of targets) {
    const component = target === 'appbar'
      ? {
          comp_name: 'appbar',
          template_name: 'wf_appbar',
          page_id: pageInfo?.pageID,
          page_title: pageInfo?.pageTitle
        }
      : componentByName.get(target);
    if (!component?.template_name) continue;

    const workflowName = component.template_name === 'wf_appbar' ? 'page-chrome' : 'hydrate-guide';
    const result = await callWorkflow(workflowName, {
      ...(component.template_name === 'wf_appbar'
        ? {
            ...(email ? { email } : {}),
            ...(component.page_id ? { page_id: component.page_id } : {}),
            ...(component.page_title ? { page_title: component.page_title } : {})
          }
        : {
            template_name: component.template_name,
            source: 'wf-server',
            format: 'html',
            ...(email ? { email } : {})
          })
    });

    updates.push({
      target,
      html: normalizeHtml(result),
      swapMode: swapMode || 'innerHTML'
    });
  }

  return updates;
}

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
    const steps = Array.isArray(action.actions) ? action.actions : [];
    let targets = normalizeTargets(action.targets);
    let redirectUrl = null;

    for (const step of steps) {
      const actionName = String(step?.action || '').toLowerCase();

      if (actionName === 'setvals') {
        const vals = getSetVals(step, selectedValue);
        if (vals.length > 0) {
          await callWorkflow('setvals', { email, vals });

          const accountValue = vals.find(({ param_name }) => param_name === 'account_id')?.param_val;
          if (accountValue) {
            req.session.account_id = accountValue;
          }
        }
      }

      if (actionName === 'hydrate') {
        const stepTargets = normalizeTargets(step.targets);
        if (stepTargets.length > 0) {
          targets = stepTargets;
        }
      }

      if (actionName === 'redirect') {
        redirectUrl = step.payload?.url;
      }
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
