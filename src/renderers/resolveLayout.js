import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { normalizeHtml } from './normalizeHtml.js';

export async function resolveLayout(components) {
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

  const navCssResult = await callWorkflow('server-query', {
    query: "SELECT css FROM studio.css WHERE class = 'appbar-nav'",
    params: {},
    source: 'server'
  });
  const navCss = (Array.isArray(navCssResult) && navCssResult[0]?.css)
    ? `<style>\n${navCssResult[0].css}\n</style>`
    : '';

  const navBarWithCss = navCss + '\n' + navHtml;

  const appbarComponent = components.find(c => c.comp_name === 'appbar');
  const appbarHtml = appbarComponent ? buildHtmxDiv(appbarComponent) : '';
  const combinedAppbar = appbarHtml + '\n' + navBarWithCss;

  layoutHtml = layoutHtml.replace('{{slot:appbar}}', combinedAppbar);

  return layoutHtml;
}
