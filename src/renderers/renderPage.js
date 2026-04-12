import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { wrapHtml } from './wrapHtml.js';

let cachedRoutes = [];

export function setRoutes(routes) {
  cachedRoutes = routes;
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
    const html = typeof loginTemplate === 'string'
      ? loginTemplate : loginTemplate?.html || loginTemplate?.[0]?.html || '';
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

  let pageInfo, components;
  try {
    const structure = await callWorkflow('page_structure', { email });
    pageInfo = structure?.pageInfo;
    components = structure?.components || [];
    if (!pageInfo?.templateName) {
      return res.status(404).send('Page template not found');
    }
  } catch (e) {
    return res.status(500).send('Failed to fetch page structure');
  }

  const templateResult = await callWorkflow('hydrate-guide', {
    template_name: pageInfo.templateName, source: 'wf-server'
  });
  let html = typeof templateResult === 'string'
    ? templateResult : templateResult?.html || templateResult?.[0]?.html || '';

  for (const comp of components) {
    if (comp.slot_name) {
      html = html.replace(`{{slot:${comp.slot_name}}}`, buildHtmxDiv(comp));
    }
  }

  html = html.replace(
    /\{\{slot:(\w+)\}\}/g,
    '<div style="background:#f8f9fa;border:2px dashed #d1d5db;padding:16px;margin:8px 0;text-align:center;color:#9ca3af;font-size:14px"><strong>SLOT:</strong> $1</div>'
  );

  res.send(wrapHtml(pageInfo.pageTitle || pageInfo.pageName, html));
}
