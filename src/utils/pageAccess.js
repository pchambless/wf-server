import { callWorkflow } from './n8nClient.js';

// Who may see a page or a template (task 859). The rule lives in the database: studio.f_page_access_ok and
// studio.f_template_access_ok read the appbar menu's visibility (global_staff: role 1; account_owner: role 1 or
// an owner of the current account). Only a handful of templates are restricted, so that list is kept for a minute
// and ordinary templates cost no extra query.
const RESTRICTED_TTL_MS = 60000;
let restricted = { at: 0, names: null };

async function serverQuery(query, params) {
  return callWorkflow('server-query', { query, params, source: 'page-access' });
}

async function restrictedTemplates() {
  if (restricted.names && Date.now() - restricted.at < RESTRICTED_TTL_MS) return restricted.names;
  const rows = await serverQuery('SELECT template_name FROM studio.f_restricted_templates()', {});
  const names = new Set((Array.isArray(rows) ? rows : []).map((r) => r?.template_name).filter(Boolean));
  restricted = { at: Date.now(), names };
  return names;
}

export async function pageAllowed(email, pageId) {
  if (!email || !/^\d+$/.test(String(pageId))) return false;
  const rows = await serverQuery('SELECT studio.f_page_access_ok(:email, :page_id) AS ok', { email, page_id: Number(pageId) });
  return (Array.isArray(rows) ? rows[0] : rows)?.ok === true;
}

// A lookup failure throws, so callers fail closed.
export async function templateAllowed(email, templateName) {
  if (!templateName) return true;
  let names = null;
  try {
    names = await restrictedTemplates();
  } catch {
    names = null; // list unavailable: check this template directly
  }
  if (names && !names.has(templateName)) return true;
  if (!email) return false;
  const rows = await serverQuery('SELECT studio.f_template_access_ok(:email, :template) AS ok', { email, template: templateName });
  return (Array.isArray(rows) ? rows[0] : rows)?.ok === true;
}
