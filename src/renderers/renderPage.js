import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { wrapHtml } from './wrapHtml.js';

let cachedRoutes = [];

function normalizeHtml(html) {
  if (!html) return '';

  if (typeof html === 'string') {
    return html.replace(/\\n/g, '\n');
  }

  if (Array.isArray(html)) {
    for (const item of html) {
      const normalized = normalizeHtml(item);
      if (normalized) return normalized;
    }
    return '';
  }

  if (typeof html === 'object') {
    if (typeof html.html === 'string' && html.html.length > 0) {
      return html.html.replace(/\\n/g, '\n');
    }

    if (html.data) {
      const fromData = normalizeHtml(html.data);
      if (fromData) return fromData;
    }
    if (html.body) {
      const fromBody = normalizeHtml(html.body);
      if (fromBody) return fromBody;
    }
    if (html.result) {
      const fromResult = normalizeHtml(html.result);
      if (fromResult) return fromResult;
    }
    if (html.output) {
      const fromOutput = normalizeHtml(html.output);
      if (fromOutput) return fromOutput;
    }
  }

  return '';
}

export function setRoutes(routes) {
  cachedRoutes = routes;
}

function buildSlotActionsHtml(slotActions = []) {
  if (!Array.isArray(slotActions) || slotActions.length === 0) return '';

  const ordered = [...slotActions].sort((a, b) => {
    const groupA = Number(a?.group_order ?? 0);
    const groupB = Number(b?.group_order ?? 0);
    if (groupA !== groupB) return groupA - groupB;

    const compA = Number(a?.comp_order ?? 0);
    const compB = Number(b?.comp_order ?? 0);
    if (compA !== compB) return compA - compB;

    return String(a?.component_name ?? '').localeCompare(String(b?.component_name ?? ''));
  });

  const buttons = ordered
    .map((action) => {
      const id = String(action?.component_name || action?.id || 'slot_action');
      const label = String(action?.label || id);
      return `<button type="button" id="${id}" class="wf-slot-action-btn">${label}</button>`;
    })
    .join('');

  return `<div class="wf-slot-actions">${buttons}</div>`;
}

export async function renderPage(req, res, next) {
  const email = req.session?.current_user_email;
  const route = req.path;

  if (route === '/favicon.ico' || route === '/health') return next();

  const routeInfo = cachedRoutes.find(r => r.route === route);
  if (!routeInfo) return next();

  if (routeInfo.page_name === 'login') {
    const loginTemplate = await callWorkflow('hydrate-guide', {
      template_name: 'login_form', source: 'wf-server', format: 'html'
    });
    const html = normalizeHtml(
      typeof loginTemplate === 'string'
        ? loginTemplate
        : loginTemplate?.html || loginTemplate?.[0]?.html || ''
    );
    return res.send(wrapHtml(routeInfo.page_name, html));
  }

  if (!email) return res.redirect('/whatsfresh/login');

  try {
    await callWorkflow('setvals', {
      email,
      vals: [{ param_name: 'page_id', param_val: String(routeInfo.page_id) }]
    });
  } catch (e) {
    return res.status(500).send('Failed to set page context');
  }

  let pageInfo, components, slotActions;
  try {
    const structure = await callWorkflow('page-structure', { email });
    pageInfo = structure?.pageInfo;
    components = structure?.components || [];
    slotActions = structure?.slotActions || structure?.pageInfo?.slotActions || {};
    if (!pageInfo?.templateName) {
      return res.status(404).send('Page template not found');
    }

    // Inject appbar component with logout action
    const appbarComponent = {
      comp_name: 'appbar',
      template_name: 'wf_appbar',
      slot_name: 'appbar',
      page_id: pageInfo.pageID,
      page_title: pageInfo.pageTitle,
      actions: [{
        trigger: 'click',
        action: 'redirect',
        targets: [],
        payload: { url: '/whatsfresh/login' }
      }]
    };
    components.unshift(appbarComponent);
  } catch (e) {
    return res.status(500).send('Failed to fetch page structure');
  }

  const templateResult = await callWorkflow('hydrate-guide', {
    template_name: pageInfo.templateName, source: 'wf-server'
  });
  let pageHtml = normalizeHtml(
    typeof templateResult === 'string'
      ? templateResult
      : templateResult?.html || templateResult?.[0]?.html || ''
  );

  const slotComponents = new Map(
    components
      .filter(c => c.slot_name && c.comp_name !== 'appbar')
      .map(c => [c.slot_name, c])
  );
  const defaultSlotTemplateCache = new Map();
  const slotTokenRegex = /\{\{slot:([a-zA-Z0-9_-]+)(?::([a-zA-Z0-9_-]+))?\}\}/g;
  const slotTokens = [...pageHtml.matchAll(slotTokenRegex)];

  for (const match of slotTokens) {
    const token = match[0];
    const slotName = match[1];
    const defaultTemplateName = match[2];
    const component = slotComponents.get(slotName);

    if (component) {
      pageHtml = pageHtml.split(token).join(buildHtmxDiv(component));
      continue;
    }

    const actionsForSlot = Array.isArray(slotActions?.[slotName]) ? slotActions[slotName] : [];
    if (actionsForSlot.length > 0) {
      pageHtml = pageHtml.split(token).join(buildSlotActionsHtml(actionsForSlot));
      continue;
    }

    if (defaultTemplateName) {
      if (!defaultSlotTemplateCache.has(defaultTemplateName)) {
        const defaultTemplateResult = await callWorkflow('hydrate-guide', {
          template_name: defaultTemplateName,
          source: 'wf-server',
          format: 'html'
        });

        const defaultTemplateHtml = normalizeHtml(
          typeof defaultTemplateResult === 'string'
            ? defaultTemplateResult
            : defaultTemplateResult?.html || defaultTemplateResult?.[0]?.html || ''
        );

        defaultSlotTemplateCache.set(defaultTemplateName, defaultTemplateHtml);
      }

      pageHtml = pageHtml.split(token).join(defaultSlotTemplateCache.get(defaultTemplateName));
      continue;
    }

    pageHtml = pageHtml.split(token).join(
      `<div style="background:#f8f9fa;border:2px dashed #d1d5db;padding:16px;margin:8px 0;text-align:center;color:#9ca3af;font-size:14px"><strong>SLOT:</strong> ${slotName}</div>`
    );
  }

  const layoutTemplate = await callWorkflow('server-query', {
    query: "SELECT html FROM studio.html_templates WHERE name = 'wf_layout'",
    params: {},
    source: 'server'
  });
  let layoutHtml = normalizeHtml(
    (Array.isArray(layoutTemplate) && layoutTemplate[0]?.html)
      ? layoutTemplate[0].html
      : ''
  );

  // Fetch nav menu HTML and CSS from function
  const navMenuResult = await callWorkflow('server-query', {
    query: "SELECT studio.tf_nav_menu_html() as nav_html",
    params: {},
    source: 'server'
  });
  const navHtml = normalizeHtml(
    (Array.isArray(navMenuResult) && navMenuResult[0]?.nav_html)
      ? navMenuResult[0].nav_html
      : ''
  );

  // Fetch appbar-nav CSS
  const navCssResult = await callWorkflow('server-query', {
    query: "SELECT css FROM studio.css WHERE class = 'appbar-nav'",
    params: {},
    source: 'server'
  });
  const navCss = normalizeHtml(
    (Array.isArray(navCssResult) && navCssResult[0]?.css)
      ? `<style>\n${navCssResult[0].css}\n</style>`
      : ''
  );

  const navBarWithCss = navCss + '\n' + navHtml;

  const appbarComponent = components.find(c => c.comp_name === 'appbar');
  const appbarHtml = appbarComponent ? buildHtmxDiv(appbarComponent) : '';
  const combinedAppbar = appbarHtml + '\n' + navBarWithCss;
  layoutHtml = layoutHtml.replace('{{slot:appbar}}', combinedAppbar);
  layoutHtml = layoutHtml.replace('{{slot:page}}', pageHtml);

  res.send(wrapHtml(pageInfo.pageTitle || pageInfo.pageName, layoutHtml));
}
