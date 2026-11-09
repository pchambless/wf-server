import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { normalizeHtml } from './normalizeHtml.js';

// Layout template, nav menu and nav css come back from ONE server-query call (task 815), not three in a row.
// Not cached: studio.vw_nav_menus shows the Account Owner and Admin groups per user, so the nav is not the same
// for every request (Task 859 builds it per user; caching can follow then).
export async function resolveLayout(components) {
  const frame = await callWorkflow('server-query', {
    query: `SELECT (SELECT html FROM studio.html_templates WHERE name = 'wf_layout') AS html,
                   studio.tf_nav_menu_html() AS nav_html,
                   (SELECT css FROM studio.css WHERE class = 'appbar-nav') AS css`,
    params: {},
    source: 'server'
  });
  const row = (Array.isArray(frame) && frame[0]) || {};

  let layoutHtml = normalizeHtml(row.html || '');
  const navHtml = normalizeHtml(row.nav_html || '');
  const navCss = row.css ? `<style>\n${row.css}\n</style>` : '';

  const navBarWithCss = navCss + '\n' + navHtml;

  const appbarComponent = components.find(c => c.comp_name === 'appbar');
  const appbarHtml = appbarComponent ? buildHtmxDiv(appbarComponent) : '';
  const combinedAppbar = appbarHtml + '\n' + navBarWithCss;

  layoutHtml = layoutHtml.replace('{{slot:appbar}}', combinedAppbar);

  return layoutHtml;
}
