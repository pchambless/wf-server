import { callWorkflow } from '../utils/n8nClient.js';
import { wrapHtml } from './wrapHtml/index.js';
import { normalizeHtml } from './normalizeHtml.js';
import { resolveLayout } from './resolveLayout.js';
import { hydrateSlots } from './hydrateSlots.js';
import { buildCrudButtons } from './buildCrudButtons.js';

let cachedRoutes = [];

export function setRoutes(routes) {
  cachedRoutes = routes;
}

function escapeAttr(str) {
  return String(str)
    .replace(/&/g, '&amp;').replace(/'/g, '&#39;').replace(/"/g, '&quot;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function joinClasses(...parts) {
  return parts.filter(Boolean).join(' ');
}



export async function renderPage(req, res, next) {
  const email = req.session?.current_user_email;
  const route = req.path;

  if (route === '/favicon.ico' || route === '/health') return next();

  const routeInfo = cachedRoutes.find(r => r.route === route);
  if (!routeInfo) return next();

  if (routeInfo.group_name === 'public') {
    const shell = await callWorkflow('hydrate-guide', {
      template_name: 'shell-public', source: 'wf-server', format: 'html'
    });
    const formTemplate = routeInfo.page_name + '_form';
    const form = await callWorkflow('hydrate-guide', {
      template_name: formTemplate, source: 'wf-server', format: 'html'
    });

    const titleResult = await callWorkflow('server-query', {
      query: `SELECT title FROM studio.html_templates WHERE name = '${formTemplate}'`,
      params: {},
      source: 'server'
    });
    const title = Array.isArray(titleResult) ? titleResult[0]?.title || '' : '';

    const shellHtml = normalizeHtml(shell);
    const formHtml = normalizeHtml(form);
    const combined = shellHtml
      .replace('{{slot:title}}', title)
      .replace('{{slot:form}}', formHtml);
    return res.send(wrapHtml(routeInfo.page_name, combined));
  }

  if (!email) return res.redirect('/login');

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

    components.unshift({
      comp_name: 'appbar',
      template_name: 'wf_appbar',
      slot_name: 'appbar',
      page_id: pageInfo.pageID,
      page_title: pageInfo.pageTitle,
      actions: {
        click: [
          {
            action: 'clearvals',
            clear_all: true
          },
          {
            action: 'redirect',
            payload: { url: '/login' }
          }
        ]
      }
    });
  } catch (e) {
    return res.status(500).send('Failed to fetch page structure');
  }

  const templateResult = await callWorkflow('hydrate-guide', {
    template_name: pageInfo.templateName, source: 'wf-server', email
  });
  let pageHtml = normalizeHtml(templateResult);

  // Inject CRUD buttons if page is crud type
  const crudButtonsHtml = buildCrudButtons(pageInfo);
  if (crudButtonsHtml) {
    pageHtml = pageHtml.split('{{slot:page-buttons}}').join(crudButtonsHtml);
  } else {
    pageHtml = pageHtml.split('{{slot:page-buttons}}').join('');
  }

  pageHtml = await hydrateSlots(pageHtml, components, slotActions, email);

  let layoutHtml = await resolveLayout(components);
  layoutHtml = layoutHtml.replace('{{slot:page}}', pageHtml);

  res.set('Cache-Control', 'no-store');
  const pageMetaScript = `<script>window.__pageContext = { pageId: ${pageInfo.pageID}, contextKey: "${pageInfo.contextKey || 'id'}", form: "${pageInfo.formTemplate || ''}", hideCrud: ${pageInfo.hideCrud || false} };</script>`;
  res.send(wrapHtml(pageInfo.pageTitle || pageInfo.pageName, pageMetaScript + layoutHtml));
}
