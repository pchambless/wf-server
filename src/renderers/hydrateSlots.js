import { callWorkflow } from '../utils/n8nClient.js';
import { buildHtmxDiv } from './buildHtmxDiv.js';
import { buildSelectWidget } from './buildSelectWidget.js';
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

function parseSlotAttrs(attrString) {
  const attrRegex = /([a-zA-Z0-9_-]+)="([^"]*)"/g;
  const attrs = {};
  let m;
  while ((m = attrRegex.exec(attrString)) !== null) {
    attrs[m[1]] = m[2];
  }
  return attrs;
}

export async function hydrateSlots(pageHtml, components, slotActions) {
  const slotComponents = new Map(
    components
      .filter(c => c.slot_name && c.comp_name !== 'appbar')
      .map(c => [c.slot_name, c])
  );
  const defaultSlotTemplateCache = new Map();

  // Matches:
  //   {{slot:name}}
  //   {{slot:name:default_template}}
  //   {{slot:name key="value" key2="value2"}}
  const slotTokenRegex = /\{\{slot:([a-zA-Z0-9_-]+)(?::([a-zA-Z0-9_-]+))?((?:\s+[a-zA-Z0-9_-]+="[^"]*")*)\}\}/g;
  const slotTokens = [...pageHtml.matchAll(slotTokenRegex)];

  for (const match of slotTokens) {
    const token = match[0];
    const slotName = match[1];
    const defaultTemplateName = match[2] || null;
    const attrString = match[3] || '';
    const attrs = parseSlotAttrs(attrString);
    const component = slotComponents.get(slotName);

    if (component) {
      pageHtml = pageHtml.split(token).join(buildHtmxDiv(component, attrs));
      continue;
    }

    const actionsForSlot = Array.isArray(slotActions?.[slotName]) ? slotActions[slotName] : [];
    if (actionsForSlot.length > 0) {
      pageHtml = pageHtml.split(token).join(buildSlotActionsHtml(actionsForSlot));
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
      pageHtml = pageHtml.split(token).join(defaultSlotTemplateCache.get(defaultTemplateName));
      continue;
    }

    pageHtml = pageHtml.split(token).join(
      `<div style="background:#f8f9fa;border:2px dashed #d1d5db;padding:16px;margin:8px 0;text-align:center;color:#9ca3af;font-size:14px"><strong>SLOT:</strong> ${slotName}</div>`
    );
  }

  return pageHtml;
}
