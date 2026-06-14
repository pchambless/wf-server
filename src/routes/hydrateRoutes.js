import { Router } from 'express';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';
import { normalizeHtml, applySelectedAccount, compileHandlebars } from './hydrationUtils.js';
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

router.post('/hydrate', async (req, res) => {
  const { template_name, page_id, page_title } = req.body;
  const email = req.session?.current_user_email;

  logger.info('[api] Request', {
    path: '/api/hydrate',
    body: req.body
  });

  try {
    const workflowName = template_name === 'wf_appbar' ? 'page-chrome' : 'hydrate-guide';
    const contextValues = Object.fromEntries(
      Object.entries(req.body).filter(([key]) => !['template_name', 'source', 'format', 'page_id', 'page_title'].includes(key))
    );

    // Clear any null context values in DB before hydrating (e.g., Add New resets contextKey)
    const nullParams = Object.entries(contextValues)
      .filter(([, v]) => v === null || v === 'null')
      .map(([key]) => key);
    if (email && nullParams.length > 0) {
      await callWorkflow('clearvals', { email, params: nullParams });
    }

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
            ...(page_title ? { page_title } : {}),
            ...contextValues
          })
    });
    // Check for styled_html + data (new select widget pattern) before normalizing
    let rawHtml;
    logger.info('[hydrate] Result type and keys', {
      type: typeof result,
      isArray: Array.isArray(result),
      has_styled_html: !!result?.styled_html,
      has_data: !!result?.data
    });
    if (result?.styled_html && result?.data) {
      let dataArr = Array.isArray(result.data) ? result.data : [result.data];
      // For form templates with no data (INSERT mode), provide an empty object so fields render
      if (dataArr.length === 0 && template_name?.endsWith('_form')) {
        dataArr = [{}];
      }
      logger.info('[hydrate] Compiling Handlebars', { template_name, data_length: dataArr.length });
      rawHtml = compileHandlebars(result.styled_html, { data: dataArr });
      logger.info('[hydrate] Compiled HTML length', { length: rawHtml.length });
    } else {
      logger.info('[hydrate] Using normalizeHtml');
      rawHtml = normalizeHtml(result);
      if (template_name === 'user_accounts_dd') {
        rawHtml = applySelectedAccount(rawHtml, req.session?.account_id);
      }
    }

    // Resolve any {{slot:*}} tokens in the returned HTML (e.g., select widgets in forms)
    let html = rawHtml;
    if (html.includes('{{slot:')) {
      // Set f_* context values from form data before resolving slots
      const formFieldValues = Object.entries(contextValues)
        .filter(([key]) => key.startsWith('f_'))
        .map(([param_name, param_val]) => ({ param_name, param_val }));

      if (formFieldValues.length > 0) {
        await callWorkflow('setvals', { email, vals: formFieldValues });
      }

      const structure = await callWorkflow('page-structure', { email });
      const components = structure?.components || [];

      // Also fetch global components (page_id=0) for slot resolution
      const globalComponents = await callWorkflow('server-query', {
        query: "SELECT pc.id AS page_comp_id, pc.comp_name, pc.slot_name, ht.name AS template_name, ht.title AS template_title, ht.platform AS widget_type, pc.actions FROM studio.page_components pc LEFT JOIN studio.html_templates ht ON pc.html_template_id = ht.id WHERE pc.page_id = 0 AND pc.deleted_at IS NULL",
        params: {},
        source: 'server'
      });

      const allComponents = [...components, ...(Array.isArray(globalComponents) ? globalComponents : [])];
      html = await resolveInlineSlots(html, allComponents);
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

export default router;
