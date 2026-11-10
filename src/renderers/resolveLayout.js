import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { normalizeHtml } from './normalizeHtml.js';

// Layout template, nav menu and nav css come back from ONE server-query call (task 815), not three in a row.
// Not cached: studio.vw_nav_menus shows the Account Owner and Admin groups per user. The signed-in email is set for
// this one statement (set_config local) so the menu is built for this user, never from a setting another request
// left on the pooled connection (task 859).
export async function resolveLayout(components, email) {
  const frame = await callWorkflow('server-query', {
    query: `WITH _ctx AS (SELECT set_config('app.current_email', :email, true))
            SELECT (SELECT html FROM studio.html_templates WHERE name = 'wf_layout') AS html,
                   (SELECT studio.tf_nav_menu_html() FROM _ctx) AS nav_html,
                   (SELECT css FROM studio.css WHERE class = 'appbar-nav') AS css`,
    params: { email: email || '' },
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
