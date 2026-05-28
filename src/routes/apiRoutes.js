import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';
import { parseAction, normalizeTargets, getSetVals } from './actionUtils.js';
import { normalizeHtml, applySelectedAccount, hydrateTargets } from './hydrationUtils.js';
import { buildHtmxDiv } from '../renderers/buildHtmxDiv.js';
import { buildSelectWidget } from '../renderers/buildSelectWidget.js';

const router = Router();

async function resolveInlineSlots(html, components) {
  if (!html || !html.includes('{{slot:')) return html;

  const componentsBySlot = new Map(
    components
      .filter(c => c.slot_name)
      .map(c => [c.slot_name, c])
  );

  const slotTokenRegex = /\{\{slot:([a-zA-Z0-9_-]+)(?::([a-zA-Z0-9_-]+))?((?:\s+[a-zA-Z0-9_-]+="[^"]*")*)\}\}/g;
  const tokens = [...html.matchAll(slotTokenRegex)];
  const unresolvedSlots = tokens.filter(m => !componentsBySlot.has(m[1]));

  if (unresolvedSlots.length > 0) {
    const globalComponents = await callWorkflow('server-query', {
      query: "SELECT pc.id AS page_comp_id, pc.comp_name, pc.slot_name, ht.name AS template_name, ht.platform AS widget_type, pc.actions FROM studio.page_components pc LEFT JOIN studio.html_templates ht ON pc.html_template_id = ht.id WHERE pc.page_id = 0 AND pc.deleted_at IS NULL",
      params: {},
      source: 'server'
    });
    if (Array.isArray(globalComponents)) {
      for (const gc of globalComponents) {
        if (gc.slot_name && !componentsBySlot.has(gc.slot_name)) {
          componentsBySlot.set(gc.slot_name, gc);
        }
      }
    }
  }

  for (const match of tokens) {
    const token = match[0];
    const slotName = match[1];
    const attrString = match[3] || '';
    const attrs = {};
    const attrRegex = /([a-zA-Z0-9_-]+)="([^"]*)"/g;
    let m;
    while ((m = attrRegex.exec(attrString)) !== null) {
      attrs[m[1]] = m[2];
    }

    const component = componentsBySlot.get(slotName);
    if (component) {
      const builder = (component.widget_type === 'select' || component.comp_name.endsWith('_dd'))
        ? buildSelectWidget : buildHtmxDiv;
      html = html.split(token).join(builder(component, attrs));
    }
  }

  return html;
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
    const rawHtml = template_name === 'user_accounts_dd'
      ? applySelectedAccount(normalizeHtml(result), req.session?.account_id)
      : normalizeHtml(result);

    // Resolve any {{slot:*}} tokens in the returned HTML (e.g., select widgets in forms)
    let html = rawHtml;
    if (html.includes('{{slot:')) {
      const structure = await callWorkflow('page-structure', { email });
      const components = structure?.components || [];
      html = await resolveInlineSlots(html, components);
    }

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

router.post('/report', async (req, res) => {
  const email = req.session?.current_user_email;
  if (!email) return res.status(401).type('text').send('Unauthorized');

  const { templates, ...contextParams } = req.body;
  if (!Array.isArray(templates) || templates.length === 0) {
    return res.status(400).type('text').send('templates array required');
  }

  logger.info('[api] Request', { path: '/api/report', templates, contextParams });

  try {
    const parts = await Promise.all(
      templates.map(template_name =>
        callWorkflow('hydrate-guide', {
          template_name,
          source: 'wf-server',
          format: 'html',
          email,
          ...contextParams
        }).then(r => normalizeHtml(r))
      )
    );
    res.type('html').send(parts.join(''));
  } catch (err) {
    logger.error('[api] Response', { path: '/api/report', success: false, error: err.message });
    res.status(500).type('text').send('Report generation failed');
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
