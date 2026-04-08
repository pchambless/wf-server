import { callWorkflow, N8N_BASE } from '../utils/n8nClient.js';

function buildHtmxDiv(component) {
  const { comp_name, template_name } = component;
  const vals = JSON.stringify({ template_name, source: 'wf-server' });
  return `<div id="${comp_name}"
     hx-post="${N8N_BASE}/webhook/hydrate-guide"
     hx-trigger="load"
     hx-vals='${vals}'
     hx-swap="innerHTML">
  </div>`;
}

export async function renderPage(req, res, next) {
  const email = req.session?.current_user_email;
  const route = req.path;

  // Skip non-page requests
  if (route === '/favicon.ico' || route === '/health') return next();

  // Fetch routes to validate this is a real page
  let routes = [];
  try {
    const routeData = await callWorkflow('hydrate-guide', {
      template_name: 'api_routes', source: 'wf-server', format: 'json'
    });
    routes = Array.isArray(routeData) ? routeData : routeData?.data || [];
  } catch (e) {
    return next();
  }
  const routeInfo = routes.find(r => r.route === route);

  if (!routeInfo) return next();

  // Login page doesn't need session
  if (routeInfo.page_name === 'login') {
    const loginTemplate = await callWorkflow('hydrate-guide', {
      template_name: 'login_form', source: 'wf-server', format: 'html'
    });
    console.log('[pageRenderer] login response:', typeof loginTemplate, JSON.stringify(loginTemplate)?.substring(0, 200));
    const html = typeof loginTemplate === 'string'
      ? loginTemplate : loginTemplate?.html || loginTemplate?.[0]?.html || '';
    return res.send(wrapHtml(routeInfo.page_name, html));
  }

  // All other pages need auth
  if (!email) return res.redirect('/whatsfresh/login');

  // Set page context
  await callWorkflow('setvals', {
    email,
    vals: [{ param_name: 'page_id', param_val: String(routeInfo.page_id) }]
  });

  // Get page structure
  const structure = await callWorkflow('hydrate-guide', {
    template_name: 'api_page_structure', source: 'wf-server'
  });
  const page = Array.isArray(structure) ? structure[0] : structure;
  const pageData = page?.api_page_structure || page;
  const pageInfo = pageData?.pageInfo;
  const components = pageData?.components || [];

  if (!pageInfo?.templateName) {
    return res.status(404).send('Page template not found');
  }

  // Get styled page template
  const templateResult = await callWorkflow('hydrate-guide', {
    template_name: pageInfo.templateName, source: 'wf-server'
  });
  let html = typeof templateResult === 'string'
    ? templateResult : templateResult?.html || templateResult?.[0]?.html || '';

  // Replace slots with HTMX self-hydrating divs
  for (const comp of components) {
    if (comp.slot_name) {
      html = html.replace(`{{slot:${comp.slot_name}}}`, buildHtmxDiv(comp));
    }
  }

  // Clear any unfilled slots
  html = html.replace(/\{\{slot:\w+\}\}/g, '');

  res.send(wrapHtml(pageInfo.pageTitle || pageInfo.pageName, html));
}

function wrapHtml(title, body) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title || 'WhatsFresh'}</title>
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
</head>
<body>
  ${body}
</body>
</html>`;
}
