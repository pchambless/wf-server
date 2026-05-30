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

function parseObjectLike(value, fallback = {}) {
  if (!value) return fallback;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : fallback;
    } catch {
      return fallback;
    }
  }
  return value && typeof value === 'object' && !Array.isArray(value) ? value : fallback;
}

function parseButtons(value, fallback = []) {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : fallback;
    } catch {
      return fallback;
    }
  }
  return fallback;
}

function triggerToLabel(trigger) {
  const base = String(trigger || '').replace(/_click$/i, '').replace(/_/g, ' ').trim();
  if (!base) return 'Action';
  return base.replace(/\b\w/g, (ch) => ch.toUpperCase());
}

function buildContextButtons(components) {
  return components
    .filter(c => c.slot_name === 'context-btn')
    .sort((a, b) => (a.ordr ?? 0) - (b.ordr ?? 0))
    .map(c => {
      const componentData = parseObjectLike(c.data, {});
      const id = componentData.id || c.comp_name;
      const actions = parseObjectLike(c.actions, {});
      const parsedButtons = parseButtons(componentData.buttons, []);
      const actionEntries = Object.entries(actions).filter(([, cfg]) => cfg && typeof cfg === 'object' && !Array.isArray(cfg));

      const configuredButtons = parsedButtons.length > 0
        ? parsedButtons
        : actionEntries.length > 0
          ? actionEntries.map(([trigger, cfg]) => ({
              label: cfg.label || triggerToLabel(trigger),
              trigger
            }))
          : [{ label: componentData.label || c.comp_name, trigger: componentData.trigger || 'button_click' }];

      const buttonsHtml = configuredButtons
        .map((btn) => {
          const label = btn?.label || c.comp_name;
          const trigger = btn?.trigger || 'button_click';
          const extraClass = typeof btn?.className === 'string' ? btn.className.trim() : '';
          const className = joinClasses('wf-slot-action-btn', 'wf-context-btn', extraClass);
          return `<button type="button" class="${escapeAttr(className)}" data-trigger="${escapeAttr(trigger)}">${escapeAttr(label)}</button>`;
        })
        .join('');

      return `<div id="${escapeAttr(id)}" class="wf-slot-actions wf-context-btn-group" style="display:none" data-actions='${escapeAttr(JSON.stringify(actions))}'>${buttonsHtml}</div>`;
    })
    .join('');
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
    return res.send(wrapHtml(routeInfo.page_name, normalizeHtml(loginTemplate)));
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

    components.unshift({
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
  const contextBtnsHtml = buildContextButtons(components);
  const allButtonsHtml = (crudButtonsHtml || '') + contextBtnsHtml;
  if (allButtonsHtml) {
    pageHtml = pageHtml.split('{{slot:page-buttons}}').join(allButtonsHtml);
  }

  pageHtml = await hydrateSlots(pageHtml, components, slotActions, email);

  let layoutHtml = await resolveLayout(components);
  layoutHtml = layoutHtml.replace('{{slot:page}}', pageHtml);

  res.set('Cache-Control', 'no-store');
  res.send(wrapHtml(pageInfo.pageTitle || pageInfo.pageName, layoutHtml));
}
