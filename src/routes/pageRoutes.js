import express from 'express';
import { callWorkflow } from '../utils/n8nClient.js';

const router = express.Router();
let routeCache = null;

async function loadRoutes() {
  const rows = await callWorkflow('json', {
    function: 'studio.tf_routes',
    params: {},
    format: 'json'
  });
  const data = Array.isArray(rows) ? rows : rows.data || [];
  routeCache = new Map();
  for (const r of data) {
    routeCache.set(r.route, r);
  }
  console.log(`[pageRoutes] Loaded ${routeCache.size} routes`);
  return routeCache;
}

async function getStyledTemplate(templateId) {
  const rows = await callWorkflow('json', {
    function: 'studio.tf_template_styled',
    params: { p_template_id: templateId },
    format: 'json'
  });
  const data = Array.isArray(rows) ? rows : rows.data || [];
  return data[0] || null;
}

async function getPageStructure(pageId) {
  const rows = await callWorkflow('json', {
    function: 'studio.tf_page_structure',
    params: { p_page_id: pageId },
    format: 'json'
  });
  const data = Array.isArray(rows) ? rows : rows.data || [];
  return data[0]?.page_structure || null;
}

function renderComponent(component, styledTemplates) {
  const template = styledTemplates.get(component.id);
  let html = template ? template.styled_html : `<div id="${component.id}"></div>`;

  if (component.children && component.children.length > 0) {
    const childrenHtml = component.children
      .map(child => renderComponent(child, styledTemplates))
      .join('\n');
    html = html.replace('{{children}}', childrenHtml);
  }

  return `<div id="${component.id}">${html}</div>`;
}

function buildPage(pageInfo, renderedHTML, cssBlocks) {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${pageInfo.pageName} - ${pageInfo.appName}</title>
  <link rel="icon" href="/icons/favicon.ico">
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
</head>
<body>
  ${renderedHTML}
</body>
</html>`;
}

router.get('/:appName/:pageName', async (req, res) => {
  try {
    if (!routeCache) await loadRoutes();

    const route = '/' + req.params.appName.toLowerCase() + '/' + req.params.pageName.toLowerCase();
    const routeInfo = routeCache.get(route);

    if (!routeInfo) {
      return res.status(404).json({ error: 'Route not found' });
    }

    const structure = await getPageStructure(routeInfo.page_id);
    if (!structure) {
      return res.status(500).json({ error: 'Failed to load page structure' });
    }

    const styledTemplates = new Map();
    const components = structure.components || [];

    for (const comp of components) {
      // TODO: resolve html_template_id from page_components once tf_page_structure includes it
      // For now, fetch by component css_style matching
      const allComps = [comp, ...(comp.children || [])];
      for (const c of allComps) {
        if (c.html_template_id) {
          const tmpl = await getStyledTemplate(c.html_template_id);
          if (tmpl) styledTemplates.set(c.id, tmpl);
        }
      }
    }

    const renderedHTML = components
      .map(comp => renderComponent(comp, styledTemplates))
      .join('\n');

    const html = buildPage(structure.pageInfo, renderedHTML);
    res.send(html);

  } catch (error) {
    console.error('[pageRoutes] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export { loadRoutes };
export default router;
