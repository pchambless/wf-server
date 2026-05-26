import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { normalizeHtml } from './normalizeHtml.js';

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

async function processSlotTokens(html, slotComponents, slotActions, defaultSlotTemplateCache, templateCache) {
  const slotTokenRegex = /\{\{slot:([a-zA-Z0-9_-]+)(?::([a-zA-Z0-9_-]+))?\}\}/g;
  const slotTokens = [...html.matchAll(slotTokenRegex)];
  let modified = false;

  for (const match of slotTokens) {
    const token = match[0];
    const slotName = match[1];
    const defaultTemplateName = match[2];
    const component = slotComponents.get(slotName);

    if (component) {
      let componentHtml;

      // For components with templates, fetch and hydrate the template first
      if (component.html_template_id) {
        const templateId = String(component.html_template_id);
        if (!templateCache.has(templateId)) {
          // Fetch template name by ID from the database
          const templateLookup = await callWorkflow('server-query', {
            query: `select name from studio.html_templates where id = ${templateId}`,
            params: {},
            source: 'wf-server'
          });

          const templateName = templateLookup?.[0]?.name;
          if (templateName) {
            const templateResult = await callWorkflow('hydrate-guide', {
              template_name: templateName,
              source: 'wf-server',
              format: 'html'
            });
            templateCache.set(templateId, normalizeHtml(templateResult));
          }
        }
        componentHtml = templateCache.get(templateId) || buildHtmxDiv(component);
      } else {
        componentHtml = buildHtmxDiv(component);
      }

      html = html.split(token).join(componentHtml);
      modified = true;
      continue;
    }

    const actionsForSlot = Array.isArray(slotActions?.[slotName]) ? slotActions[slotName] : [];
    if (actionsForSlot.length > 0) {
      html = html.split(token).join(buildSlotActionsHtml(actionsForSlot));
      modified = true;
      continue;
    }

    if (defaultTemplateName) {
      if (!defaultSlotTemplateCache.has(defaultTemplateName)) {
        const defaultTemplateResult = await callWorkflow('hydrate-guide', {
          template_name: defaultTemplateName,
          source: 'wf-server',
          format: 'html'
        });
        defaultSlotTemplateCache.set(defaultTemplateName, normalizeHtml(defaultTemplateResult));
      }
      html = html.split(token).join(defaultSlotTemplateCache.get(defaultTemplateName));
      modified = true;
      continue;
    }

    html = html.split(token).join(
      `<div style="background:#f8f9fa;border:2px dashed #d1d5db;padding:16px;margin:8px 0;text-align:center;color:#9ca3af;font-size:14px"><strong>SLOT:</strong> ${slotName}</div>`
    );
    modified = true;
  }

  return { html, modified };
}

export async function hydrateSlots(pageHtml, components, slotActions) {
  const slotComponents = new Map(
    components
      .filter(c => c.slot_name && c.comp_name !== 'appbar')
      .map(c => [c.slot_name, c])
  );
  const defaultSlotTemplateCache = new Map();
  const templateCache = new Map();

  let html = pageHtml;
  let hasSlots = true;

  while (hasSlots) {
    const { html: processedHtml, modified } = await processSlotTokens(html, slotComponents, slotActions, defaultSlotTemplateCache, templateCache);
    html = processedHtml;
    hasSlots = modified;
  }

  return html;
}
